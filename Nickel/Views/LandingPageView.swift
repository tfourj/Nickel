//
//  LandingPageView.swift
//  Nickel
//
//  Created by TfourJ on 13. 4. 25.
//

import SwiftUI

struct LandingPageView: View {
    @Binding var completedVersion: Int
    let currentVersion: Int
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            Group {
                if currentPage == 0 {
                    // First page
                    VStack(spacing: 30) {
                        Image("Nickel")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                        
                        Text("Welcome to Nickel")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("A native iOS client that integrates with Cobalt.tools API")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Spacer()
                        
                        // Page dots indicator moved above the button
                        HStack(spacing: 8) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(currentPage == index ? Color.white : Color.gray.opacity(0.5))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.bottom, 20)
                        
                        Button {
                            currentPage = 1
                        } label: {
                            Text("Next")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                                .padding(.horizontal, 40)
                        }
                    }
                    .padding()
                } else if currentPage == 1 {
                    // Second page
                    VStack(spacing: 30) {
                        Image(systemName: "arrow.down.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.blue)
                        
                        Text("Download to Photos app")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Save videos, photos, audio from your favorite platforms to your device")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(currentPage == index ? Color.white : Color.gray.opacity(0.5))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.bottom, 20)
                        
                        Button {
                            currentPage = 2
                        } label: {
                            Text("Next")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                                .padding(.horizontal, 40)
                        }
                    }
                    .padding()
                } else {
                    // Third page
                    VStack(spacing: 30) {
                        Image(systemName: "gearshape.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.blue)
                        
                        Text("Setup")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("You'll need to configure your API settings before using Nickel")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("• Open settings tab")
                                .foregroundColor(.white)
                            Text("• Add your API instance URL (you can also browse public instances)")
                                .foregroundColor(.white)
                            Text("• (OPTIONAL) Change authentication method and add your custom API-Key/Bearer")
                                .foregroundColor(.white)
                        }
                        .padding()
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(currentPage == index ? Color.white : Color.gray.opacity(0.5))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.bottom, 20)

                        Button(action: {
                            if let url = URL(string: "https://getnickel.site/discord") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "message.circle.fill")
                                    .foregroundColor(.white)
                                Text("Join Discord Community")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .cornerRadius(10)
                            .padding(.horizontal, 40)
                        }

                        Button {
                            completedVersion = currentVersion
                            UserDefaults.standard.set(currentVersion, forKey: "landingPageVersion")
                            logOutput("Landing page completed - version \(currentVersion)")
                        } label: {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                                .padding(.horizontal, 40)
                        }
                    }
                    .padding()
                }
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width > 100 && currentPage > 0 {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                }
        )
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var completedVersion: Int = 0
        let currentVersion: Int = 1

        var body: some View {
            LandingPageView(
                completedVersion: $completedVersion,
                currentVersion: currentVersion
            )
        }
    }

    return PreviewWrapper()
}
