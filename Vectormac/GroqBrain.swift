//
//  GroqBrain.swift
//  Vectormac
//
//  Groq API client — Jarvis's neural network
//

import Foundation

class GroqBrain: ObservableObject {
    
    static let shared = GroqBrain()
    
    private let apiURL = "https://api.groq.com/openai/v1/chat/completions"
    private let model = "llama-3.3-70b-versatile"
    
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: "groq_api_key")
        }
    }
    
    var hasAPIKey: Bool { !apiKey.isEmpty }
    
    private var conversationHistory: [[String: String]] = []
    
    private var systemPrompt: String {
        """
        You are J.A.R.V.I.S. (Just A Rather Very Intelligent System), Tony Stark's personal AI assistant, \
        but you serve user Ariz Azadov — a computer science student at CVUT (Czech Technical University in Prague).

        Rules:
        - Respond as Jarvis would — intelligent, calm, witty, and slightly formal.
        - Address the user as "sir" occasionally.
        - Keep responses concise (1-3 sentences max) since they are spoken aloud.
        - You have dry British wit. Use it sparingly.
        - You know the current date/time: \(Date.now.formatted(date: .complete, time: .shortened)).
        - Never use markdown, emojis, or special characters — your responses are read by a speech synthesizer.
        - If asked about systems, report real macOS system stats when provided.
        """
    }
    
    init() {
        // Load from UserDefaults first, then try config file
        if let saved = UserDefaults.standard.string(forKey: "groq_api_key"), !saved.isEmpty {
            self.apiKey = saved
        } else if let configKey = GroqBrain.loadKeyFromConfig() {
            self.apiKey = configKey
        } else {
            self.apiKey = ""
        }
    }
    
    /// Load API key from ~/.jarvis_config file
    private static func loadKeyFromConfig() -> String? {
        let path = NSHomeDirectory() + "/.jarvis_config"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("GROQ_API_KEY=") {
                let key = String(trimmed.dropFirst("GROQ_API_KEY=".count)).trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : key
            }
        }
        return nil
    }
    
    func clearHistory() {
        conversationHistory = []
    }
    
    func ask(_ message: String) async -> String {
        guard hasAPIKey else {
            return "Sir, I need a Groq API key to access my neural network. Please configure it in settings."
        }
        
        conversationHistory.append(["role": "user", "content": message])
        
        // Keep last 20 messages
        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }
        
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        messages.append(contentsOf: conversationHistory)
        
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 150,
            "top_p": 0.9
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return "Internal serialization error, sir."
        }
        
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return "Connection issue with my neural network, sir."
            }
            
            if httpResponse.statusCode == 401 {
                return "The API key appears invalid, sir. Please check settings."
            }
            
            guard httpResponse.statusCode == 200 else {
                return "Neural network returned status \(httpResponse.statusCode), sir."
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: String],
               let content = message["content"] {
                
                let reply = content.trimmingCharacters(in: .whitespacesAndNewlines)
                conversationHistory.append(["role": "assistant", "content": reply])
                return reply
            }
            
            return "I'm having trouble parsing the response, sir."
        } catch {
            return "Neural network connection interrupted, sir. Check your internet."
        }
    }
}
