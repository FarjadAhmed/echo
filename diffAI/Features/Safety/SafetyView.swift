import SwiftUI

/// Safety: a very large SOS button, who it calls, where the user is, and the two other ways to get help.
/// Nothing on this screen acts on its own: every button goes through the conversation engine,
/// which reads out what will happen and waits for the user's yes.
struct SafetyView: View {
    @EnvironmentObject private var contacts: ContactsDirectory
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var conversation: ConversationEngine
    @EnvironmentObject private var speechOutput: SpeechOutputCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulsing = false

    private var contactName: String { contacts.emergencyContact.name }
    private var emergencyNumber: String { ActionExecutor.emergencyServicesNumber }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                VStack(spacing: 16) {
                    sosButton
                    Text("Calls your emergency contact and offers to text your caregivers with your location. You confirm before anything is sent.")
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)

                RowGroup {
                    HStack(spacing: 16) {
                        IconTile(systemName: "phone.fill", color: Color(.systemGreen))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Emergency contact")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                            Text(contactName)
                                .font(.headline)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: Theme.minTapHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Emergency contact: \(contactName)")
                    RowDivider()
                    locationRow
                }

                VStack(spacing: 12) {
                    Button {
                        conversation.submitTyped("call emergency services")
                    } label: {
                        Label("Call \(emergencyNumber), emergency services", systemImage: "phone.arrow.up.right.fill")
                            .labelStyle(BigLabelStyle())
                    }
                    .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                    .accessibilityLabel("Call \(emergencyNumber), emergency services")
                    .accessibilityHint("Calls the police, ambulance or fire service after you confirm")

                    Button {
                        router.open(.caregiver)
                    } label: {
                        Label("Caregiver dashboard", systemImage: "person.2.fill")
                            .labelStyle(BigLabelStyle())
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Caregiver dashboard")
                    .accessibilityHint("Opens the demo dashboard for a caregiver")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .echoBackground()
        .navigationTitle("Safety")
        .onAppear {
            pulsing = !reduceMotion
            Task { await speechOutput.announceScreen(AppScreen.safety.announcement) }
        }
    }

    // MARK: - SOS

    private var sosButton: some View {
        Button {
            conversation.submitTyped("help me")
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.danger.opacity(0.12))
                    .scaleEffect(!reduceMotion && pulsing ? 1.0 : 0.9)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulsing)
                Circle()
                    .fill(Theme.danger.gradient)
                    .padding(22)
                    .shadow(color: Theme.danger.opacity(0.3), radius: 10, y: 4)
                VStack(spacing: 4) {
                    Image(systemName: "sos")
                        .font(.system(size: 52, weight: .bold))
                    Text("Emergency")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(.horizontal, 36)
                .foregroundStyle(.white)
            }
            .frame(width: 230, height: 230)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Emergency")
        .accessibilityHint("Calls \(contactName) and offers to text your caregivers with your location. You will be asked to confirm first.")
    }

    // MARK: - Location

    private var locationRow: some View {
        Button {
            conversation.submitTyped("where am i")
        } label: {
            HStack(spacing: 16) {
                IconTile(systemName: "location.fill", color: Color(.systemBlue))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your location")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(location.lastKnownDescription ?? "Not checked yet. Tap to find out.")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapHeight, alignment: .leading)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your location: \(location.lastKnownDescription ?? "not checked yet")")
        .accessibilityHint("Finds your location and says the address")
        .accessibilityAddTraits(.isButton)
    }
}
