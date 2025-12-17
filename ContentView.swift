//
//  ContentView.swift
//  Solvelt AI
//
//  Created by Layton Lannan on 11/25/25.
//

import SwiftUI
import PhotosUI  //For picking a photo
import UIKit
///OpenAI API key for authentication

let OPENAI_API_KEY = "YOUR_API_KEY"
    //Main View

struct ContentView: View {
    //The currently selected photo item from the photo picker
    @State private var selectedItem: PhotosPickerItem? = nil
    
    //The loaded UIImage to display and analyze
    @State private var selectedImage: UIImage? = nil
    
    //The AI-generated explanation text
    @State private var resultText: String = ""
    
    //Loading state for API request
    @State private var isLoading = false
    
    //Body
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                //Header section
                Text("Solvelt AI")
                    .font(.largeTitle)
                    .bold()
                Text("Take a photo of a homework problem and get a step-by-step explanation.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                //Image display section
                //Show selected image (if any)
                if let uiImage = selectedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(12)
                        .padding(.horizontal)
                } else {
                    //Placeholder when no image is selected
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .frame(height: 200)
                        .overlay(
                            Text("No image selected yet")
                                .foregroundColor(.gray)
                            
                        )
                        .padding(.horizontal)
                    
                }
                // Pick a photo button
                //User can pick a photo from their phone
                PhotosPicker(selection: $selectedItem,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Text("Choose a Photo")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                             .padding(.horizontal)
                             .task(id: selectedItem) {
                                 //Automatically load the image when a new item is selected
                                 if let newItem = selectedItem {
                                     await loadImage(from: newItem)
                                 }
                             }
                
                //Analyze button
                Button {
                    analyzeHomework()
                } label: {
                    if isLoading {
                        //show progress indicator while waiting for API response
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Explain This Problem")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .disabled(selectedImage == nil || isLoading)// Disable if no image or loading
                .background((selectedImage == nil ? Color.gray : Color.green).opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                
                
                //Result section
                ScrollView {
                    Text(resultText.isEmpty ? "Your explanation will appear here." : resultText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                Spacer()
                
            }
            .padding(.top)
            .navigationTitle("Homework Helper")
            
        }
    }
    //Load the chosen image into UIImage
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        
        do {
            //Attempt to load the image data and convert to UIImage
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
                resultText = ""//Clear the previous result when new image is loaded
            }
        } catch {
            print("Error loading image: \(error)")
        }
    }
    //Sends the selected image to OpenAI's GPT-4 Vision API for homework analysis
    private func analyzeHomework() {
        guard let selectedImage = selectedImage else { return }
        isLoading = true
        resultText = ""
        
        Task {
            do {
                //Image encoding
                //UIImage to JPEG data with compression
                guard let jpegData = selectedImage.jpegData(compressionQuality: 0.7) else {
                    throw NSError(
                        domain: "ImageError",
                        code: 0,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Could not convert image to JPEG."
                        ])
                }
                //Encode Image as base64 string for API transmission
                let base64Image = jpegData.base64EncodedString()
                //Configure API request
                let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.addValue("Bearer \(OPENAI_API_KEY)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                //Construct request body with vision model
                let body: [String: Any] = [
                    "model": "gpt-4o-mini",
                    "messages": [[
                        "role": "user",
                        "content": [
                            [
                                "type": "text",
                                "text": "You are a friendly tutor. Explain this homework problem step-by-step so a college student can understand."
                            ],
                            [
                                "type": "image_url",
                                "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
                            ]
                        ]
                    ]],
                "max_tokens": 1000 //Limit response length
                ]
                //Serialize the body to JSON data
                request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                //API Call
                //Send request and await response
                let (data, response) = try await URLSession.shared.data(for: request)
                //Error Handling
                //Check for HTTP errors
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw NSError(
                        domain: "HTTPError",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: errorText]
                    )
                }
                //Response Parsing
                //Parse JSON response to extract the explanation
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let choices = obj?["choices"] as? [[String: Any]]
                let message = choices?.first?["message"] as? [String: Any]
                let explanation = message?["content"] as? String
                    ?? "AI returned an unexpected format"
                //Update UI on main thread with the explanation
                await MainActor.run {
                    self.resultText = explanation
                    self.isLoading = false
                }
                
            } catch {
                //Handle errors and update UI on main thread
                await MainActor.run {
                    self.resultText = "Error: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
            
        }
    }
}
