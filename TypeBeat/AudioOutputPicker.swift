import SwiftUI
import AVKit

struct AudioOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.activeTintColor = .black
        view.tintColor = .black
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
