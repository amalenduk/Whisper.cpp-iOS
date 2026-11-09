//
//  Whisper_cpp_iOSApp.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import SwiftUI

@main
struct Whisper_cpp_iOSApp: App {
    
    @State private var whisperViewModel = WhisperTranscribeViewModel()
    @State private var nativeViewModel = NativeSpeechViewModel()
    
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView(viewModel: whisperViewModel)
                    .tabItem {
                        Label("Whisper.cpp", systemImage: "waveform")
                    }
                
                NativeSpeechContentView(viewModel: nativeViewModel)
                    .tabItem {
                        Label("Apple Speech", systemImage: "apple.logo")
                    }
            }
        }
    }
}
