import Foundation

@main
private enum TranslationEndpointPolicyHarness {
    static func main() {
        precondition(TranslationEndpointPolicy.allows(URLComponents(string: "https://api.example.com/v1")!))
        precondition(TranslationEndpointPolicy.allows(URLComponents(string: "http://127.0.0.1:11434/v1")!))
        precondition(TranslationEndpointPolicy.allows(URLComponents(string: "http://localhost:11434/v1")!))
        precondition(!TranslationEndpointPolicy.allows(URLComponents(string: "http://api.example.com/v1")!))
        precondition(!TranslationEndpointPolicy.allows(URLComponents(string: "file:///tmp/provider")!))
        print("translation_endpoint_policy=PASS")
    }
}
