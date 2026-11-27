import ArcKit
import SwiftUI

// Watch Together's screens (docs/plans/watch-together.md): Home's row, the invite panel, the
// lobby, the player's section and the notice capsule. Glass and white, with no UI colour.

/// Home's Watch Together row, at the top while there are rooms: one wide card per room and a
/// last card for joining with a code.
struct WatchTogetherRow: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    /// The page's focus (Home's rows).
    var focus: FocusState<String?>.Binding

    var body: some View {
        let together = browse.together
        VStack(alignment: .leading, spacing: 16) {
            Text(L("together.title")).font(.title3.weight(.semibold)).padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 36) {
                    ForEach(together.rooms, id: \.id) { room in
                        RoomCard(room: room, item: together.titles[room.item.id], focus: focus,
                                 focusKey: "top|" + room.id)
                    }
                    JoinCodeCard { together.enteringCode = true }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
    }
}

/// A room on Home: the title's background with a "Watch Together" capsule, then who's hosting
/// and who's there. Select joins; holding Select offers Join and Decline (Cancel for the host).
private struct RoomCard: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let room: ListedRoom
    let item: Item?
    var focus: FocusState<String?>.Binding
    let focusKey: String
    @State private var busy = false

    private let size = CardStyle.thumb.size

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Button { join() } label: {
                ZStack(alignment: .topLeading) {
                    ArtworkImage(path: item.flatMap { MediaCard(item: $0).backdrop })
                        .frame(width: size.width, height: size.height)
                        .clipped()
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .center)
                    Label(room.isPlaying ? L("together.watching_now") : L("together.title"), systemImage: "person.2.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(12)
                    if busy { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            .focused(focus, equals: focusKey)
            .accessibilityLabel(L("together.card_label", room.item.title))
            .contextMenu {
                Button { join() } label: {
                    Label(room.joined ? L("together.return") : L("together.join"), systemImage: "play.fill")
                }
                Button(role: .destructive) { dismiss() } label: {
                    Label(room.hosting ? L("together.cancel_room") : L("together.decline"), systemImage: "xmark")
                }
            }
            VStack(alignment: .center, spacing: 2) {
                Text(item?.isEpisode == true ? item?.seriesTitle ?? room.item.title : room.item.title)
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Text(room.hosting ? L("together.you_host") : L("together.hosted_by", room.hostName))
                    .font(.caption2).lineLimit(1)
                if let people = peopleLine {
                    Text(people).font(.caption2).foregroundStyle(ArcColor.muted).lineLimit(1)
                }
            }
            .frame(width: size.width)
            .belowLiftedCard(focus.wrappedValue == focusKey)
        }
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

/// The row's last card: join someone's room with their code.
private struct JoinCodeCard: View {
    let action: () -> Void
    private let size = CardStyle.thumb.size

    var body: some View {
        VStack(spacing: 10) {
            Button(action: action) {
                VStack(spacing: 12) {
                    Image(systemName: "keyboard").font(.title2)
                    Text(L("together.join_with_code")).font(.callout.weight(.semibold))
                }
                .frame(width: size.width, height: size.height)
                .background(ArcColor.surface2)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            Text(" ").font(.caption)
        }
    }
}

/// Choose who to invite: a glass panel down the right-hand side (as the player's options), so the
/// title stays in view. Done makes the room, or adds people to the room this device is in.
struct InvitePanel: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let target: WatchTogetherModel.InviteTarget
    @State private var people: [WatchPerson]?
    @State private var failed = false
    @State private var chosen: Set<String> = []
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("together.title")).font(.title3.weight(.bold))
                    Text(target.roomId == nil ? L("together.invite_body", target.title) : L("together.invite_more_body"))
                        .font(.callout).foregroundStyle(ArcColor.muted)
                }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let people {
                            if people.isEmpty {
                                Text(L("together.nobody")).font(.callout).foregroundStyle(ArcColor.muted)
                            }
                            ForEach(people) { person in personRow(person) }
                        } else if failed {
                            Text(L("together.people_failed")).font(.callout).foregroundStyle(ArcColor.muted)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .focusSection()
                if let problem { Text(problem).font(.callout).foregroundStyle(ArcColor.muted) }
                HStack(spacing: 20) {
                    Button { done() } label: {
                        HStack {
                        if busy { ProgressView() }
                        Text(L("together.done"))
                    }.frame(maxWidth: .infinity)
                    }
                    .arcGlassButton(prominent: true)
                    .disabled(chosen.isEmpty || busy)
                    if target.roomId == nil {
                        Button(L("together.use_code")) { useCode() }.arcGlassButton()
                    }
                }
                .focusSection()
            }
            .padding(40)
            .frame(width: 680)
            .frame(maxHeight: .infinity)
            .arcGlassPanel(cornerRadius: 40)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .padding(.vertical, 60)
            .padding(.trailing, 60)
        }
        .onExitCommand { browse.together.inviting = nil }
        .task { await load() }
    }

    private func personRow(_ person: WatchPerson) -> some View {
        let on = chosen.contains(person.id)
        return Button {
            if on { chosen.remove(person.id) } else { chosen.insert(person.id) }
        } label: {
            HStack(spacing: 20) {
                Avatar(name: person.name, color: person.color, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).font(.callout.weight(.semibold))
                    if !person.canWatch {
                        Text(L("together.cant_watch")).font(.caption2)
                    } else if person.friend {
                        Text(L("together.friend")).font(.caption2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.title3)
            }
            .frame(maxWidth: .infinity)
        }
        .arcGlassButton(prominent: on)
        .buttonBorderShape(.capsule)
        .disabled(!person.canWatch)
        .accessibilityLabel(person.name)
        .accessibilityValue(on ? L("together.chosen") : "")
    }

    private func load() async {
        guard let api = app.api else { return }
        do {
            people = try await api.watchPeople(itemId: target.itemId)
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

/// Typing someone's room code: eight letters and digits on the TV's keyboard.
struct JoinCodeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @State private var code = ""
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 28) {
            Text(L("together.join_title")).font(.title2.weight(.bold))
            Text(L("together.join_body")).font(.callout).foregroundStyle(ArcColor.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 900)
            TextField(L("together.code_placeholder"), text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(width: 520)
            if let problem { Text(problem).font(.callout).foregroundStyle(ArcColor.muted) }
            Button { join() } label: {
                HStack {
                        if busy { ProgressView() }
                        Text(L("together.join"))
                    }.frame(width: 320)
            }
            .arcGlassButton(prominent: true)
            .disabled(WatchCode.normalize(code).count != 8 || busy)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArcColor.background.opacity(0.92))
        .onExitCommand { browse.together.enteringCode = false }
    }

    private func join() {
        guard let api = app.api else { return }
        busy = true
        problem = nil
        let together = browse.together
        Task {
            do {
                try await together.join(api, code: code)
                together.enteringCode = false
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
struct LobbyPanel: View {
    let room: WatchRoom
    let code: String?
    var focus: FocusState<PlayerScreen.PlayerFocus?>.Binding
    let start: () -> Void
    let invite: () -> Void
    let leave: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 16) {
                    Image(systemName: "person.2.fill").font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("together.title")).font(.title3.weight(.bold))
                        if let title = room.item?.title { Text(title).font(.callout).foregroundStyle(ArcColor.muted) }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("together.here", room.participants.count)).font(.caption.weight(.semibold)).foregroundStyle(ArcColor.muted)
                    PeopleList(room: room)
                }
                if room.isHost {
                    HStack(spacing: 20) {
                        Button(action: start) { Label(L("together.start"), systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .arcGlassButton(prominent: true)
                            .focused(focus, equals: .lobbyStart)
                        Button(action: invite) { Label(L("together.invite"), systemImage: "person.badge.plus") }
                            .arcGlassButton()
                        Button(L("together.leave"), action: leave).arcGlassButton()
                    }
                    .focusSection()
                    if let code { Text(L("together.share_code", code)).font(.caption).foregroundStyle(ArcColor.muted) }
                } else {
                    HStack(spacing: 20) {
                        ProgressView()
                        Text(L("together.waiting_for_host", room.hostDisplayName)).font(.callout)
                        Spacer(minLength: 0)
                        Button(L("together.leave"), action: leave).arcGlassButton()
                            .focused(focus, equals: .lobbyStart)
                    }
                }
            }
            .padding(48)
            .frame(width: 900)
            .arcGlassPanel(cornerRadius: 40)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
    }
}

/// Who's in the room, with the host's crown and each person's state, then those invited.
struct PeopleList: View {
    let room: WatchRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(room.participants) { p in
                HStack(spacing: 14) {
                    Circle().fill(p.ready ? Color.white : ArcColor.subtle).frame(width: 10, height: 10)
                    Text(p.id == room.selfId ? L("together.you", p.name) : p.name).font(.callout)
                    if p.id == room.hostId { Image(systemName: "crown.fill").font(.caption).accessibilityLabel(L("together.host")) }
                    Spacer(minLength: 0)
                    Text(status(p)).font(.caption).foregroundStyle(ArcColor.muted)
                }
            }
            ForEach(Array(room.invited.enumerated()), id: \.offset) { _, person in
                HStack(spacing: 14) {
                    Circle().strokeBorder(ArcColor.subtle, lineWidth: 1.5).frame(width: 10, height: 10)
                    Text(person.name).font(.callout).foregroundStyle(ArcColor.muted)
                    Spacer(minLength: 0)
                    Text(L("together.status_invited")).font(.caption).foregroundStyle(ArcColor.muted)
                }
            }
        }
    }

    private func status(_ p: WatchParticipant) -> String {
        if !p.available { return L("together.status_unavailable") }
        if !p.ready || p.state == "waiting" { return L("together.status_loading") }
        return p.state == "playing" ? L("together.status_watching") : L("together.status_ready")
    }
}

/// A short note at the top of the screen: "Paused by Sam", "Room ready…".
struct NoticeCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 28).padding(.vertical, 14)
            .arcGlassPanel(cornerRadius: 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 60)
            .allowsHitTesting(false)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
