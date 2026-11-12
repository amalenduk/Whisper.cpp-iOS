//
//  NativeSpeechContentView.swift
//  Whisper.cpp iOS
//
//  Created by Amalendu Kar on 07/11/26.
//

import SwiftUI

struct NativeSpeechContentView: View {
    
    @Bindable var viewModel: NativeSpeechViewModel
    
    init(viewModel: NativeSpeechViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Engine Switch Control (Toggle between Modern and Legacy)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.selectedEngineMode == .modern ? "bolt.badge.sparkle" : "clock.arrow.circlepath")
                                .foregroundStyle(viewModel.selectedEngineMode == .modern ? .blue : .orange)
                            
                            Text(viewModel.selectedEngineMode == .modern ? "Modern Engine (iOS 26+)" : "Legacy Engine (SFSpeech)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        Text(viewModel.selectedEngineMode == .modern ? "SpeechAnalyzer & Foundation Transcriber" : "SFSpeechRecognizer Audio Stream")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        if !viewModel.isModernEngineSupported {
                            Text("Modern engine requires iOS 26 or later")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $viewModel.isUsingModernEngine)
                        .labelsHidden()
                        .disabled(!viewModel.isModernEngineSupported)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                )
                
                // Error Banner / Display
                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Error")
                                .font(.headline)
                                .foregroundStyle(.red)
                            
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            viewModel.clearError()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Status & Language Header
                HStack {
                    if viewModel.isDownloadingModel {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading Model...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.isPreparing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Starting...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.isRecording ? Color.red : Color.gray)
                                .frame(width: 10, height: 10)
                            
                            Text(viewModel.isRecording ? "Listening..." : (viewModel.isStopping ? "Stopping..." : "Idle"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(viewModel.isRecording ? .red : .secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Locale Selector Menu
                    Menu {
                        ForEach(viewModel.supportedLocales) { item in
                            Button {
                                viewModel.updateLocaleAndRestart(identifier: item.identifier)
                            } label: {
                                HStack {
                                    Text(item.name)
                                    if viewModel.selectedLocaleIdentifier == item.identifier {
                                        Image(systemName: "checkmark")
                                    } else if !item.isInstalled {
                                        Image(systemName: "icloud.and.arrow.down")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(viewModel.selectedLocaleDisplayName)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.blue.opacity(0.12)))
                        .foregroundStyle(.blue)
                    }
                }
                
                // Active Engine Identifier & Tokens Bar
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                        Text(viewModel.engineDescription)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if !viewModel.tokens.isEmpty {
                        Text("\(viewModel.tokens.count) tokens")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.15)))
                    }
                }
                
                // Full Transcript Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Full Transcript")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if !viewModel.fullTranscript.isEmpty {
                            HStack(spacing: 12) {
                                Button {
                                    UIPasteboard.general.string = viewModel.fullTranscript
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .font(.caption)
                                
                                Button("Clear") {
                                    viewModel.clearTranscript()
                                }
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        }
                    }
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(viewModel.fullTranscript.isEmpty ? "Transcription will appear here..." : viewModel.fullTranscript)
                                .font(.body)
                                .foregroundStyle(viewModel.fullTranscript.isEmpty ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding()
                                .id("bottom")
                        }
                        .onChange(of: viewModel.fullTranscript) {
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Partial Text Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Partial / In-Progress")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(viewModel.partialText.isEmpty ? "—" : viewModel.partialText)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(viewModel.partialText.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if viewModel.isRecording && !viewModel.partialText.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
                
                // Controls: Start / Stop Buttons
                HStack(spacing: 16) {
                    Button {
                        viewModel.start()
                    } label: {
                        Label("Start", systemImage: "mic.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(viewModel.isRecording || viewModel.isStopping || viewModel.isPreparing)
                    
                    Button {
                        viewModel.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!viewModel.isRecording || viewModel.isStopping)
                }
                .padding(.top, 4)
            }
            .padding()
            .navigationTitle("Live Speech")
        }
    }
}

#Preview {
    NativeSpeechContentView(viewModel: NativeSpeechViewModel())
}
