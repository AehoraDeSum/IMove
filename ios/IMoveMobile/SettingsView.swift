import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var address = ""
    @State private var code = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Label("MAC CONNECTION", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.caption.weight(.bold)).foregroundColor(IMoveTheme.mint)
                    if store.connection != nil {
                        Text("Paired").font(.title2.bold())
                        Text(store.address).font(.footnote.monospaced()).textSelection(.enabled)
                        Text(store.status?.ready == true ? "USB device ready" : "Connected to the Mac; check the USB device")
                            .foregroundColor(IMoveTheme.quiet)
                        ActionButton(title: "Refresh connection", icon: "arrow.clockwise", secondary: true) {
                            Task { await store.refreshAll() }
                        }
                        ActionButton(title: "Remove pairing", icon: "rectangle.portrait.and.arrow.right", secondary: true) {
                            store.disconnect()
                        }
                    } else {
                        Text("Tailscale HTTPS address").font(.caption).foregroundColor(IMoveTheme.quiet)
                        TextField("https://mac-adi.tailnet.ts.net", text: $address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(12).background(IMoveTheme.background, in: RoundedRectangle(cornerRadius: 10))
                        Text("32-character pairing code").font(.caption).foregroundColor(IMoveTheme.quiet)
                        SecureField("Code from the Mac app", text: $code)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(12).background(IMoveTheme.background, in: RoundedRectangle(cornerRadius: 10))
                        ActionButton(title: "Connect to Mac", icon: "link") {
                            Task {
                                await store.connect(address: address, code: code)
                                if store.connection != nil { code = "" }
                            }
                        }
                        .disabled(Connection(address: address, code: code) == nil)
                    }
                    Text(store.message).font(.caption).foregroundColor(IMoveTheme.quiet)
                }

                Card {
                    Text("Setup").font(.title3.bold())
                    Text("1. Keep IMove and the USB connection running on the Mac. Start the control page on the Remote access screen.")
                    Text("2. Sign the Mac and this iPhone or iPad in to the same Tailscale account. Run `tailscale serve --bg 8765` on the Mac.")
                    Text("3. Enter the private HTTPS address shown by the Mac and the IMove pairing code above.")
                    Text("The target USB iPhone does not need Tailscale. Do not use Funnel; Serve stays on your private network.")
                        .foregroundColor(IMoveTheme.quiet)
                }

                Card {
                    Text("Location permissions").font(.title3.bold())
                    Text("While-in-use location access is enough for one-off sends. For background tracking the app may ask for 'Always' access; iOS does not guarantee an exact 5-minute interval with the screen off.")
                        .foregroundColor(IMoveTheme.quiet)
                }
            }
            .padding()
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Connection")
        .imovePage()
    }
}
