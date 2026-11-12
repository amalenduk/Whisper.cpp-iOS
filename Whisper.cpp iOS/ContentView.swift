//
//  ContentView.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import SwiftUI

struct ContentView: View {
    
    @State private var viewModel = NativeSpeechViewModel()
    
    init() {}
    
    var body: some View {
        NativeSpeechContentView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
