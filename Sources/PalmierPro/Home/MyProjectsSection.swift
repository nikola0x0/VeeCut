import SwiftUI

/// The latest project as a card to pick up, then the rest as a list with search, selection and delete.
struct MyProjectsSection: View {
    @State private var searchQuery = ""
    @State private var isSearchExpanded = false
    @State private var isSelecting = false
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var projectsPendingDeletion: [ProjectEntry] = []
    @State private var deletionMessage: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if let latest = latestEntry {
                    sectionTitle(L10n.string("Pick up where you left off"))
                    LatestProjectCard(entry: latest, onDelete: { requestDeletion([latest]) })
                        .padding(.bottom, AppTheme.Spacing.md)
                }
                toolbar
                projectList
            }
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The newest project gets the card unless the list is being searched or edited.
    private var latestEntry: ProjectEntry? {
        guard !isSelecting, searchQuery.isEmpty else { return nil }
        return ProjectRegistry.shared.sortedEntries.first
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.semibold))
            .foregroundStyle(AppTheme.Text.secondaryColor)
    }

    private var toolbar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            sectionTitle(latestEntry == nil ? L10n.string("Projects") : L10n.string("Other projects"))

            Spacer()

            if isSearchExpanded {
                searchField
                    .frame(width: AppTheme.ComponentSize.projectSearchWidth)
                    .transition(.opacity.combined(with: .scale(scale: AppTheme.Opacity.prominent, anchor: .trailing)))
            } else {
                Button {
                    isSearchExpanded = true
                    Task { isSearchFocused = true }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                        .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Search projects"))
                .help(L10n.string("Search projects"))
            }

            if isSelecting {
                Button(L10n.string("Delete \(selectedProjectIDs.count)"), role: .destructive) {
                    prepareDeletion()
                }
                .buttonStyle(.capsule(fill: AnyShapeStyle(AppTheme.Status.errorColor)))
                .disabled(selectedProjectIDs.isEmpty)
                Button(L10n.string("Done")) { endSelection() }
                    .buttonStyle(.capsule)
            } else if !ProjectRegistry.shared.entries.isEmpty {
                Button(L10n.string("Select")) { isSelecting = true }
                    .buttonStyle(.capsule)
            }
        }
        .animation(.easeInOut(duration: AppTheme.Anim.transition), value: isSearchExpanded)
        .alert(deletionTitle, isPresented: Binding(
            get: { !projectsPendingDeletion.isEmpty },
            set: { if !$0 { projectsPendingDeletion = [] } }
        )) {
            Button(L10n.string("Cancel"), role: .cancel) { projectsPendingDeletion = [] }
            Button(L10n.string("Delete"), role: .destructive) { deletePendingProjects() }
        } message: {
            Text(deletionPrompt)
        }
        .alert(L10n.string("Projects Couldn’t Be Deleted"), isPresented: Binding(
            get: { deletionMessage != nil },
            set: { if !$0 { deletionMessage = nil } }
        )) {
            Button(L10n.string("OK")) { deletionMessage = nil }
        } message: {
            Text(verbatim: deletionMessage ?? String())
        }
        .onChange(of: ProjectRegistry.shared.entries.map(\.id)) { _, ids in
            selectedProjectIDs.formIntersection(ids)
            if ids.isEmpty { endSelection() }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.mutedColor)
            TextField(L10n.string("Search projects"), text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: AppTheme.FontSize.sm))
                .focused($isSearchFocused)
                .onExitCommand { collapseSearch() }
            if !searchQuery.isEmpty {
                Button(action: collapseSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.mutedColor)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(L10n.string("Clear search"))
            }
        }
        .padding(.leading, AppTheme.Spacing.smMd)
        .padding(.trailing, AppTheme.Spacing.xs)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.Interaction.fill(AppTheme.Opacity.subtle))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    AppTheme.Interaction.fill(AppTheme.Opacity.faint),
                    lineWidth: AppTheme.BorderWidth.thin
                )
        )
        .onChange(of: isSearchFocused) { _, focused in
            if !focused, searchQuery.isEmpty { isSearchExpanded = false }
        }
    }

    private var projectList: some View {
        let entries = filteredEntries.filter { $0.id != latestEntry?.id }
        return LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            if entries.isEmpty, !searchQuery.isEmpty {
                Text(L10n.string("No projects found"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
                    .padding(.vertical, AppTheme.Spacing.xl)
            } else {
                ForEach(entries) { entry in
                    ProjectRow(
                        entry: entry,
                        isSelecting: isSelecting,
                        isSelected: selectedProjectIDs.contains(entry.id),
                        onSelect: { toggleSelection(entry.id) },
                        onDelete: { requestDeletion([entry]) }
                    )
                }
            }
        }
    }

    private var filteredEntries: [ProjectEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ProjectRegistry.shared.sortedEntries }
        return ProjectRegistry.shared.sortedEntries.filter { $0.name.localizedStandardContains(query) }
    }

    private var deletionTitle: String {
        projectsPendingDeletion.count == 1
            ? L10n.string("Delete Project?")
            : L10n.string("Delete Selected Projects?")
    }

    private var deletionPrompt: String {
        projectsPendingDeletion.count == 1
            ? L10n.string("The project will be moved to the Trash.")
            : L10n.string("The selected projects will be moved to the Trash.")
    }

    private func toggleSelection(_ id: UUID) {
        if selectedProjectIDs.contains(id) {
            selectedProjectIDs.remove(id)
        } else {
            selectedProjectIDs.insert(id)
        }
    }

    private func collapseSearch() {
        searchQuery = ""
        isSearchFocused = false
        isSearchExpanded = false
    }

    private func endSelection() {
        isSelecting = false
        selectedProjectIDs.removeAll()
    }

    private func prepareDeletion() {
        let selected = ProjectRegistry.shared.entries.filter { selectedProjectIDs.contains($0.id) }
        requestDeletion(selected)
    }

    private func requestDeletion(_ entries: [ProjectEntry]) {
        let open = openProjects(in: entries)
        guard open.isEmpty else {
            deletionMessage = L10n.string("Close \(open.map(\.name).formatted()) before deleting.")
            return
        }
        projectsPendingDeletion = entries
    }

    private func deletePendingProjects() {
        let ids = Set(projectsPendingDeletion.map(\.id))
        projectsPendingDeletion = []
        Task {
            do {
                let result = try await AppState.shared.deleteProjects(withIDs: ids)
                selectedProjectIDs.subtract(result.deletedIDs)
                if result.failedNames.isEmpty {
                    endSelection()
                } else {
                    deletionMessage = L10n.string("Couldn’t move \(result.failedNames.formatted()) to the Trash.")
                }
            } catch {
                deletionMessage = error.localizedDescription
            }
        }
    }

    private func openProjects(in entries: [ProjectEntry]) -> [ProjectEntry] {
        let paths = Set(AppState.shared.openProjects.compactMap { $0.fileURL?.standardizedFileURL.path })
        return entries.filter { paths.contains($0.url.standardizedFileURL.path) }
    }
}
