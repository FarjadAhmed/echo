import PhotosUI
import SwiftUI

/// Live camera with a huge shutter, quick modes, and a photo-picker and sample fallback for devices without a camera.
struct CameraView: View {
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var service = CameraService()

    @State private var liveReady = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var modeTaps = 0
    @State private var shutterTaps = 0

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                if liveReady {
                    CameraPreview(session: service.session)
                        .accessibilityHidden(true)
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .strokeBorder(Theme.separator, lineWidth: 0.5)
                        )
                    shutter
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            IconTile(systemName: "camera.fill", color: Color(.systemGray))
                            Text("No camera here")
                                .font(.headline)
                                .foregroundStyle(Theme.text)
                        }
                        Text("The camera is not available on this device. Choose a photo from your library, or try a sample photo.")
                            .font(.title3)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .accessibilityElement(children: .combine)

                    PhotosPicker(selection: $pickedItem, matching: .images) {
                        // The frame sits inside the label so the whole area is tappable.
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                            .labelStyle(BigLabelStyle())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityLabel("Choose a photo")
                    .accessibilityHint("Opens your photo library")

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(text: "Sample photos")
                        RowGroup {
                            ForEach(Array(SamplePhotos.all.enumerated()), id: \.element.id) { index, sample in
                                if index > 0 { RowDivider() }
                                FeatureRow(title: sample.name, systemImage: "photo", color: Color(.systemIndigo), hint: "Uses a sample photo") {
                                    analyzeSample(sample)
                                }
                            }
                        }
                    }
                }
                modeChips
            }
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .echoBackground()
        .navigationTitle("Camera")
        .sensoryFeedback(.selection, trigger: modeTaps) { _, _ in settings.hapticsEnabled }
        .sensoryFeedback(.impact(weight: .heavy), trigger: shutterTaps) { _, _ in settings.hapticsEnabled }
        .task { await setUp() }
        .onDisappear { service.stop() }
        .onChange(of: camera.pendingPurpose) { _, _ in handlePending() }
        .onChange(of: pickedItem) { _, item in loadPicked(item) }
    }

    /// The huge round shutter. Its value says which mode the photo will use.
    private var shutter: some View {
        Button {
            shutterTaps += 1
            Task { await capture(camera.mode) }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.accent, lineWidth: 5)
                Circle()
                    .fill(Theme.accent)
                    .padding(11)
                Image(systemName: "camera.fill")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: Theme.shutterSize, height: Theme.shutterSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Take photo")
        .accessibilityValue(modeTitle(camera.mode))
        .accessibilityHint("Takes a photo for the mode you picked")
    }

    private var modeChips: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "Mode")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    modeChip("Describe scene", symbol: "camera.viewfinder", .describe)
                    modeChip("Read text", symbol: "text.viewfinder", .readText)
                    modeChip("Scan a document", symbol: "doc.text.viewfinder", .scanDocument)
                    modeChip("Identify color", symbol: "paintpalette", .identifyColor)
                    NavChip(title: "Find object", systemImage: "magnifyingglass", hint: "Explains how to find an object by voice") {
                        Task { await speechOutput.say("To find something, say where is my, then the object. For example, where is my cup.") }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func modeChip(_ title: String, symbol: String, _ mode: CapturePurpose) -> some View {
        NavChip(title: title, systemImage: symbol, hint: "Sets the mode for the next photo", isSelected: camera.mode == mode) {
            modeTaps += 1
            camera.mode = mode
            let next = liveReady ? "Say take photo, or tap the big button." : "Choose a photo below."
            Task { await speechOutput.say("\(title) selected. \(next)") }
        }
    }

    private func modeTitle(_ mode: CapturePurpose) -> String {
        switch mode {
        case .describe: return "Describe scene"
        case .readText: return "Read text"
        case .scanDocument: return "Scan a document"
        case .identifyColor: return "Identify color"
        case .findObject(let target): return "Find \(target)"
        }
    }

    private func setUp() async {
        liveReady = await service.start()
        if liveReady && camera.pendingPurpose != nil {
            // Opened by a voice request: no intro, just "Hold still" and the photo.
            handlePending()
            return
        }
        let intro = liveReady
            ? "Camera. Say take photo, or tap the big button."
            : "Camera. The camera is not available on this device. Choose a photo, or try a sample photo."
        await speechOutput.announceScreen(intro)
        handlePending()
    }

    /// A voice request ("what is this?", "read this") that arrived before or while the camera was open.
    private func handlePending() {
        guard let purpose = camera.pendingPurpose else { return }
        guard liveReady else {
            Task { await speechOutput.say("Choose a photo below, and I will \(purpose.prompt.lowercased()).") }
            return
        }
        _ = camera.takePendingRequest()
        Task {
            await speechOutput.say("Hold still.")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await capture(purpose)
        }
    }

    private func capture(_ purpose: CapturePurpose) async {
        guard let image = await service.capture() else {
            await speechOutput.say("I could not take that photo. Please try again.")
            return
        }
        conversation.analyze(image, purpose: purpose)
    }

    private func analyzeSample(_ sample: SamplePhoto) {
        let purpose = camera.takePendingRequest() ?? camera.mode
        conversation.analyze(sample.image, purpose: purpose, sampleDescription: sample.description)
    }

    private func loadPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            pickedItem = nil
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await speechOutput.say("I could not open that photo. Please choose another.")
                return
            }
            let purpose = camera.takePendingRequest() ?? camera.mode
            conversation.analyze(image, purpose: purpose)
        }
    }
}
