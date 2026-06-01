import SwiftUI

/// Bottom Activity drawer — live console for the active streaming job (install /
/// upgrade / uninstall). Mirrors the Tauri `ActivityDrawer`: collapsed shows a
/// one-line status; expanded shows the scrolling output with copy + cancel.
/// Mounted as a bottom safe-area inset on the detail container.
struct ActivityDrawer: View {
    @Bindable var model: AppModel

    /// The drawer shows the explicitly-active job only. nil `activeJobId`
    /// (after Close) hides the drawer entirely; selecting a job in the Activity
    /// panel or starting a new one re-populates it.
    private var job: ActivityJob? {
        guard let id = model.activeJobId else { return nil }
        return model.jobs.first { $0.id == id }
    }

    /// Status-aware header label. The job's stored `label` is the in-progress
    /// form ("Installing X"); on completion show the terminal form so a green ✓
    /// doesn't sit next to "Installing".
    static func displayLabel(_ job: ActivityJob) -> String {
        switch job.status {
        case .running:   return job.label
        case .succeeded: return job.label
                .replacingOccurrences(of: "Installing ", with: "Installed ")
                .replacingOccurrences(of: "Upgrading ", with: "Upgraded ")
                .replacingOccurrences(of: "Uninstalling ", with: "Uninstalled ")
        case .failed:    return "Failed: \(job.label)"
        case .canceled:  return "Canceled: \(job.label)"
        }
    }

    var body: some View {
        if let job {
            VStack(spacing: 0) {
                Divider()
                header(job)
                if model.drawerOpen {
                    console(job)
                }
            }
            // Full bleed edge-to-edge so the bar covers the window's rounded
            // bottom corners (no dark notch where the split-view corner shows
            // through). .bar material fills the whole width.
            .frame(maxWidth: .infinity)
            .background(.bar)
            // Auto-collapse the console when a job finishes successfully — keeps
            // the one-line status visible (+ in Activity history) without the
            // 200px console lingering. Failures stay expanded so the error is seen.
            .onChange(of: job.status) { _, status in
                if status == .succeeded { model.drawerOpen = false }
            }
        }
    }

    private func header(_ job: ActivityJob) -> some View {
        HStack(spacing: 8) {
            statusIcon(job.status)
            Text(Self.displayLabel(job)).font(.callout.weight(.medium)).lineLimit(1)
            if job.status == .running {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if job.status == .running {
                Button {
                    model.cancelJob(job.id)
                } label: { Label("Cancel", systemImage: "stop.circle") }
                .buttonStyle(.borderless)
            }
            Button {
                copyLog(job)
            } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless)
            .help("Copy output")
            Button {
                model.drawerOpen.toggle()
            } label: {
                Image(systemName: model.drawerOpen ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.borderless)
            .help(model.drawerOpen ? "Collapse" : "Expand")
            // Close — dismiss the drawer for this job (stays in Activity history).
            // Cancels first if it's still running. Mirrors the Tauri drawer's X.
            Button {
                if job.status == .running { model.cancelJob(job.id) }
                model.dismissDrawer()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .onTapGesture { model.drawerOpen.toggle() }
    }

    private func console(_ job: ActivityJob) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(job.lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(line.stream == .stderr ? .orange : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(height: 200)
            .onChange(of: job.lines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: ActivityJob.JobStatus) -> some View {
        switch status {
        case .running:   Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .canceled:  Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
    }

    private func copyLog(_ job: ActivityJob) {
        let text = job.lines.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// The Activity panel — job history. Click a job to open it in the drawer.
struct ActivityView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Installs, upgrades, and uninstalls show up here.")
                )
            } else {
                List(model.jobs) { job in
                    Button {
                        model.activeJobId = job.id
                        model.drawerOpen = true
                    } label: {
                        HStack(spacing: 10) {
                            icon(job.status)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.label).fontWeight(.medium)
                                Text(job.command).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(job.status.rawValue.capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbar {
            if model.jobs.contains(where: { $0.status != .running }) {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Finished") { model.clearFinishedJobs() }
                }
            }
        }
    }

    @ViewBuilder
    private func icon(_ status: ActivityJob.JobStatus) -> some View {
        switch status {
        case .running:   Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .canceled:  Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
    }
}
