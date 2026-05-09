import Foundation
import Combine
import UIKit

final class KeyboardObserver: ObservableObject {
    @Published var isVisible: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in
                self?.isVisible = true
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in
                self?.isVisible = false
            }
            .store(in: &cancellables)
    }
}
