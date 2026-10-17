import SwiftUI

/// Camera-based tools in one place, as a grid of cards.
struct ToolsView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var camera: CameraController
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                LazyVGrid(columns: columns, spacing: 12) {
                    QuickActionCard(title: "Read text", systemImage: "text.viewfinder", hint: "Point the camera at a label, sign or page, and hear the text", color: Color(.systemOrange)) {
                        openCamera(.readText)
                    }
                    QuickActionCard(title: "Identify color", systemImage: "paintpalette", hint: "Point the camera at something to hear its main color", color: Color(.systemPink)) {
                        openCamera(.identifyColor)
                    }
                    QuickActionCard(title: "Describe scene", systemImage: "camera.viewfinder", hint: "Take a photo and hear what is in it", color: Color(.systemIndigo)) {
                        openCamera(.describe)
                    }
                    QuickActionCard(title: "Scan a document", systemImage: "doc.text.viewfinder", hint: "Photograph a letter or form and hear a short summary", color: Color(.systemBlue)) {
                        conversation.submitTyped("scan this document")
                    }
                }

                Button {
                    router.open(.history)
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .labelStyle(BigLabelStyle())
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("History")
                .accessibilityHint("Your last 20 descriptions and readings")
            }
            .padding(.horizontal, 20)
            .padding(.vertical)
        }
        .echoBackground()
        .navigationTitle("Tools")
        .onAppear {
            Task { await speechOutput.announceScreen(AppScreen.tools.announcement) }
        }
    }

    private func openCamera(_ purpose: CapturePurpose) {
        camera.request(purpose)
        router.open(.camera)
    }
}
