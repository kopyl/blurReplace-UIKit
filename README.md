*Vibe coded*

A replacement for this from SwiftUI:

```swift
struct ContentView: View {
    @State private var isHello = true
    var body: some View {
        Button {
            isHello.toggle()
        } label: {
            Text(isHello ? "Hello" : "World")
                .font(.system(size: 100))
            .transition(.blurReplace)
            .id(isHello)
        }
    }
}
```
