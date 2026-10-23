// SplashView.swift

import SwiftUI

struct SplashView: View {

    @State private var scale: CGFloat = 0.7
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .frame(width: 96, height: 96)
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .scaleEffect(scale)
                    .opacity(opacity)

                Text("VoCo")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(opacity)

                Text("Voice-Powered Vocational Training")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("VoCo loading")
    }
}
