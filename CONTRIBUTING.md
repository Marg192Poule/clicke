# Contributing to Clické

Thank you for your interest in contributing to Clické! 🎉

## Ways to Contribute

- 🐛 **Report bugs** — Open an issue describing the problem
- 💡 **Suggest features** — Share your ideas for improvements
- 📝 **Improve documentation** — Fix typos, add examples
- 💻 **Submit code** — Fix bugs or implement new features

## Development Setup

### Prerequisites

- macOS 14.0 Sonoma or later (macOS 15+ for Liquid Glass effects)
- Xcode 16.0 or later
- Git

### Getting Started

1. Fork the repository on GitHub

2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/clicke.git
   cd clicke
   ```

3. Open in Xcode:
   ```bash
   open clické.xcodeproj
   ```

4. Build and run (⌘R)

## Code Guidelines

### Swift Style

- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable and function names
- Keep functions small and focused (single responsibility)
- Add comments for complex logic

### SwiftUI Best Practices

- Prefer `@State` for local view state
- Use `@StateObject` for owned observable objects
- Use `@ObservedObject` for passed-in observable objects
- Extract reusable views into separate structs
- Use `#Preview` for SwiftUI previews

### Project Structure

```
clické/
├── Coordinator/     # App lifecycle, windows
├── Extensions/      # Swift extensions
├── Features/        # Feature modules (Editor, Settings)
├── Managers/        # Singleton managers
├── Models/          # Data models
├── View/            # Main views
└── ViewModel/       # View models
```

### Commit Messages

Use clear, descriptive commit messages:

```
feat: Add new gradient preset
fix: Resolve slider lag on noise adjustment
docs: Update README with build instructions
refactor: Extract noise generation to separate struct
```

Prefixes:
- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation
- `refactor:` — Code refactoring
- `test:` — Tests
- `chore:` — Maintenance

## Pull Request Process

1. **Create a branch** for your feature:
   ```bash
   git checkout -b feature/amazing-feature
   ```

2. **Make your changes** and test thoroughly

3. **Commit your changes**:
   ```bash
   git commit -m "feat: Add amazing feature"
   ```

4. **Push to your fork**:
   ```bash
   git push origin feature/amazing-feature
   ```

5. **Open a Pull Request** on GitHub

### PR Checklist

- [ ] Code follows project style guidelines
- [ ] App builds without warnings
- [ ] Feature has been tested on macOS
- [ ] Documentation updated if needed
- [ ] Commit messages are clear

## Reporting Issues

### Bug Reports

When reporting bugs, please include:

- macOS version
- Xcode version (if building from source)
- Steps to reproduce
- Expected behavior
- Actual behavior
- Screenshots if applicable

### Feature Requests

When suggesting features:

- Describe the use case
- Explain the expected behavior
- Include mockups if possible

## Testing

Before submitting a PR:

1. Build the app (⌘B)
2. Run the app (⌘R)
3. Test the specific feature you changed
4. Test related features to ensure no regressions
5. Test on both Intel and Apple Silicon if possible

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Feel free to open an issue for any questions about contributing!

---

Thank you for helping make Clické better! 🙌
