import ArcKit
import SwiftUI

// Watch Together on iPhone and iPad (docs/plans/watch-together.md), on the Apple TV's room model
// (WatchTogetherModel): Home's row of rooms, choosing who to invite, joining with a code, the
// lobby and the room's sheet in the player. iOS's own sheets and lists, in Arc's glass and white.

/// Home's Watch Together row, at the top while there are rooms: a card per room, then one for
/// joining with a code.
struct MobileTogetherRow: View {
    @Environment(Browse.self) private var browse
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let wide = sizeClass == .regular
        let together = browse.together
        VStack(alignment: .leading, spacing: 10) {
            Text(L("together.title"))
                .font(.title3.weight(.bold))
                .padding(.horizontal, Metrics.margin(wide))
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: wide ? 16 : 12) {
                    ForEach(together.rooms) { room in
                        MobileRoomCard(room: room, item: together.titles[room.item.id], width: Metrics.card(.thumb, wide: wide).width)
                    }
                    Button { together.enteringCode = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "keyboard").font(.title3)
                            Text(L("together.join_with_code")).font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(ArcColor.foreground)
                        .frame(width: Metrics.card(.thumb, wide: wide).width, height: Metrics.card(.thumb, wide: wide).height)
                        .background(ArcColor.surface2, in: RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("together.code")
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Metrics.margin(wide), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// A room on Home: the title's picture with a Watch Together capsule, then who's hosting and
/// who's there. A tap joins; touching and holding offers Join and Decline (Cancel for the host).
private struct MobileRoomCard: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let room: ListedRoom
    let item: Item?
    let width: CGFloat
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { join() } label: {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay { ArtworkImage(path: item.flatMap { MediaCard(item: $0).backdrop }) }
                    .overlay(alignment: .topLeading) {
                        Label(room.isPlaying ? L("together.watching_now") : L("together.title"), systemImage: "person.2.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ArcColor.foreground)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(8)
                    }
                    .overlay { if busy { ProgressView().tint(ArcColor.foreground) } }
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(L("together.card_label", room.item.title)))
            .accessibilityIdentifier("together.room")
            .contextMenu {
                Button { join() } label: {
                    Label(room.joined ? L("together.return") : L("together.join"), systemImage: "play.fill")
                }
                Button(role: .destructive) { dismiss() } label: {
                    Label(room.hosting ? L("together.cancel_room") : L("together.decline"), systemImage: "xmark")
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item?.isEpisode == true ? item?.seriesTitle ?? room.item.title : room.item.title)
                    .font(.footnote.weight(.semibold)).lineLimit(1)
                Text(room.hosting ? L("together.you_host") : L("together.hosted_by", room.hostName))
                    .font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1)
                if let people = peopleLine {
                    Text(people).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .frame(width: width)
    }

    private var peopleLine: String? {
        if !room.participants.isEmpty {
            let names = room.participants.joined(separator: ", ")
            return room.participants.count == 1 ? L("together.is_here", names) : L("together.are_here", names)
        }
        return room.invited.isEmpty ? nil : L("together.invited", room.invited.joined(separator: ", "))
    }

    private func join() {
        guard let api = app.api, !busy else { return }
        busy = true
        Task {
            do { try await browse.together.accept(api, room) } catch {
                ArcLogApp.warn("joining a Watch Together room failed: \(type(of: error))")
                browse.together.say(L("together.join_failed"))
                await browse.together.refreshRooms(api)
            }
            busy = false
        }
    }

    private func dismiss() {
        guard let api = app.api else { return }
        Task { await browse.together.dismiss(api, room) }
    }
}

/// Choose who to invite, as a sheet: a list to tick, Done to make the room (or add them to the
/// room this device is in), and Use a Code Instead.
struct MobileInviteSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let target: WatchTogetherModel.InviteTarget
    @State private var people: [WatchPerson]?
    @State private var failed = false
    @State private var chosen: Set<String> = []
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let people {
                        if people.isEmpty {
                            Text(L("together.nobody")).foregroundStyle(ArcColor.muted)
                        }
                        ForEach(people) { person in personRow(person) }
                    } else if failed {
                        Text(L("together.people_failed")).foregroundStyle(ArcColor.muted)
                        Button(L("common.retry")) { Task { await load() } }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(target.roomId == nil ? L("together.invite_body", target.title) : L("together.invite_more_body"))
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(ArcColor.muted) }
                }
                if target.roomId == nil {
                    Section {
                        Button(L("together.use_code")) { useCode() }
                            .accessibilityIdentifier("together.use_code")
                    }
                }
            }
            .navigationTitle(L("together.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.cancel")) { browse.together.inviting = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if busy {
                        ProgressView()
                    } else {
                        Button(L("together.done")) { done() }
                            .disabled(chosen.isEmpty)
                            .accessibilityIdentifier("together.done")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    private func personRow(_ person: WatchPerson) -> some View {
        let on = chosen.contains(person.id)
        return Button {
            if on { chosen.remove(person.id) } else { chosen.insert(person.id) }
        } label: {
            HStack(spacing: 12) {
                Avatar(name: person.name, color: person.color, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.name).foregroundStyle(ArcColor.foreground)
                    if !person.canWatch {
                        Text(L("together.cant_watch")).font(.footnote).foregroundStyle(ArcColor.muted)
                    } else if person.friend {
                        Text(L("together.friend")).font(.footnote).foregroundStyle(ArcColor.muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? ArcColor.foreground : ArcColor.subtle)
            }
        }
        .disabled(!person.canWatch)
        .accessibilityLabel(Text(person.name))
        .accessibilityValue(Text(on ? L("together.chosen") : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load() async {
        guard let api = app.api else { return }
        failed = false
        do {
            people = try await api.watchPeople(itemId: target.itemId)
        } catch is CancellationError {
        } catch {
            ArcLogApp.warn("who to invite didn't load: \(type(of: error))")
            failed = true
        }
    }

    private func done() {
        guard let api = app.api, !chosen.isEmpty else { return }
        busy = true
        problem = nil
        let together = browse.together
        Task {
            do {
                if let roomId = target.roomId {
                    try await together.invite(api, roomId: roomId, people: Array(chosen))
                } else {
                    try await together.createRoom(api, itemId: target.itemId, title: target.title, people: Array(chosen))
                }
                together.inviting = nil
            } catch let error as APIError where error.status == 429 {
                problem = L("together.too_many_rooms")
            } catch {
                ArcLogApp.warn("inviting failed: \(type(of: error))")
                problem = L("together.invite_failed")
            }
            busy = false
        }
    }

    private func useCode() {
        guard let api = app.api else { return }
        let together = browse.together
        let itemId = target.itemId
        Task {
            do {
                let item = try await api.item(itemId)
                together.inviting = nil
                try await together.startWithCode(api, item: item)
            } catch {
                ArcLogApp.warn("making a room with a code failed: \(type(of: error))")
                problem = L("together.invite_failed")
            }
        }
    }
}

/// Typing someone's room code: eight letters and digits. From Home's row (as a sheet) and from
/// Settings (as a page).
struct MobileJoinCodeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    /// Joined: close whatever this was opened in (the player then opens on the room).
    let joined: () -> Void
    @State private var code = ""
    @State private var busy = false
    @State private var problem: String?
    @FocusState private var typing: Bool

    var body: some View {
        Form {
            Section {
                TextField(L("together.code_placeholder"), text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3.monospaced())
                    .focused($typing)
                    .submitLabel(.join)
                    .onSubmit(join)
                    .accessibilityIdentifier("together.code_field")
            } footer: {
                Text(problem ?? L("together.join_body"))
            }
            Section {
                Button { join() } label: {
                    HStack {
                        Text(L("together.join"))
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(WatchCode.normalize(code).count != 8 || busy)
                .accessibilityIdentifier("together.code_join")
            }
        }
        .navigationTitle(L("together.join_title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { typing = true }
    }

    private func join() {
        guard let api = app.api, WatchCode.normalize(code).count == 8, !busy else { return }
        busy = true
        problem = nil
        let together = browse.together
        Task {
            do {
                try await together.join(api, code: code)
                joined()
            } catch let error as APIError where error.status == 404 {
                problem = L("together.code_not_found")
            } catch let error as APIError where error.status == 429 {
                problem = L("together.too_many_tries")
            } catch {
                ArcLogApp.warn("joining with a code failed: \(type(of: error))")
                problem = L("together.join_failed")
            }
            busy = false
        }
    }
}

/// Before a room first plays: a glass panel over the paused, dimmed picture. The host starts it
/// (and can invite more people); everyone else waits for them.
struct MobileLobby: View {
    let room: WatchRoom
    let code: String?
    let start: () -> Void
    let invite: () -> Void
    let leave: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill").font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("together.title")).font(.headline)
                            if let title = room.item?.title { Text(title).font(.subheadline).foregroundStyle(ArcColor.muted) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("together.here", room.participants.count)).font(.caption.weight(.semibold)).foregroundStyle(ArcColor.muted)
                        MobilePeopleList(room: room)
                    }
                    if room.isHost {
                        HStack(spacing: 10) {
                            Button(action: start) { Label(L("together.start"), systemImage: "play.fill").frame(maxWidth: .infinity) }
                                .arcGlassButton(prominent: true)
                                .accessibilityIdentifier("together.start")
                            Button(action: invite) { Image(systemName: "person.badge.plus") }
                                .arcGlassButton()
                                .accessibilityLabel(Text(L("together.invite")))
                            Button(L("together.leave"), action: leave).arcGlassButton()
                        }
                        if let code { Text(L("together.share_code", code)).font(.footnote).foregroundStyle(ArcColor.muted).textSelection(.enabled) }
                    } else {
                        HStack(spacing: 12) {
                            ProgressView().tint(ArcColor.foreground)
                            Text(L("together.waiting_for_host", room.hostDisplayName)).font(.subheadline)
                            Spacer(minLength: 0)
                            Button(L("together.leave"), action: leave).arcGlassButton()
                        }
                    }
                }
                .foregroundStyle(ArcColor.foreground)
                .padding(20)
                .frame(maxWidth: 440)
                .arcGlassPanel(cornerRadius: 26)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
    }
}

/// The room from the player's Watch Together button: who's here, Invite, Leave, and End for
/// Everyone for the host.
struct MobileRoomSheet: View {
    @Environment(Browse.self) private var browse
    @Environment(\.dismiss) private var dismiss
    let invite: () -> Void
    let leave: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let room = browse.together.room {
                    Section(L("together.here", room.participants.count)) {
                        MobilePeopleList(room: room)
                    }
                    if room.isHost, let code = browse.together.lobbyCode {
                        Section { Text(L("together.share_code", code)).textSelection(.enabled) }
                    }
                    Section {
                        Button { dismiss(); invite() } label: { Label(L("together.invite"), systemImage: "person.badge.plus") }
                        Button { dismiss(); leave() } label: { Label(L("together.leave"), systemImage: "rectangle.portrait.and.arrow.right") }
                        if room.isHost {
                            Button(role: .destructive) {
                                dismiss()
                                Task { await browse.together.end() }
                            } label: { Label(L("together.end"), systemImage: "xmark.circle") }
                        }
                    }
                }
            }
            .navigationTitle(L("together.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("mobile.done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// Who's in the room, with the host's crown and each person's state, then those invited.
struct MobilePeopleList: View {
    let room: WatchRoom

    var body: some View {
        ForEach(room.participants) { p in
            HStack(spacing: 10) {
                Circle().fill(p.ready ? ArcColor.foreground : ArcColor.subtle).frame(width: 8, height: 8)
                Text(p.id == room.selfId ? L("together.you", p.name) : p.name).font(.subheadline)
                if p.id == room.hostId { Image(systemName: "crown.fill").font(.caption).accessibilityLabel(Text(L("together.host"))) }
                Spacer(minLength: 0)
                Text(status(p)).font(.caption).foregroundStyle(ArcColor.muted)
            }
        }
        ForEach(Array(room.invited.enumerated()), id: \.offset) { _, person in
            HStack(spacing: 10) {
                Circle().strokeBorder(ArcColor.subtle, lineWidth: 1.5).frame(width: 8, height: 8)
                Text(person.name).font(.subheadline).foregroundStyle(ArcColor.muted)
                Spacer(minLength: 0)
                Text(L("together.status_invited")).font(.caption).foregroundStyle(ArcColor.muted)
            }
        }
    }

    private func status(_ p: WatchParticipant) -> String {
        if !p.available { return L("together.status_unavailable") }
        if !p.ready || p.state == "waiting" { return L("together.status_loading") }
        return p.state == "playing" ? L("together.status_watching") : L("together.status_ready")
    }
}
