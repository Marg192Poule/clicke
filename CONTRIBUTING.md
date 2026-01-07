# Contributing to Clicke

## Ways to Contribute

- Report bugs by opening an issue
- Suggest features
- Improve documentation
- Submit code via pull requests

## Development Setup

### Prerequisites

- macOS 14.0 or later
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
   open clicke.xcodeproj
   ```

4. Build and run with Command + R

## Code Guidelines

### Swift Style

- Follow Swift API Design Guidelines
- Use meaningful variable and function names
- Keep functions small and focused
- Add comments for complex logic

### SwiftUI

- Use `@State` for local view state
- Use `@StateObject` for owned observable objects
- Use `@ObservedObject` for passed-in observable objects
- Extract reusable views into separate structs

### Project Structure

```
clicke/
├── Coordinator/     App lifecycle, windows
├── Extensions/      Swift extensions
├── Features/        Feature modules (Editor, Settings)
├── Managers/        Singleton managers
├── Models/          Data models
├── View/            Main views
└── ViewModel/       View models
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
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation
- `refactor:` Code refactoring
- `test:` Tests
- `chore:` Maintenance

## Pull Request Process

1. Create a branch for your feature:
   ```bash
   git checkout -b feature/your-feature
   ```

2. Make your changes and test thoroughly

3. Commit your changes:
   ```bash
   git commit -m "feat: Add your feature"
   ```

4. Push to your fork:
   ```bash
   git push origin feature/your-feature
   ```

5. Open a Pull Request on GitHub

### PR Checklist

- Code follows project style guidelines
- App builds without warnings
- Feature has been tested on macOS
- Documentation updated if needed
- Commit messages are clear

## Reporting Issues

### Bug Reports

Include:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots if applicable

### Feature Requests

Include:
- Use case description
- Expected behavior
- Mockups if possible

## Testing

Before submitting a PR:

1. Build the app (Command + B)
2. Run the app (Command + R)
3. Test the specific feature you changed
4. Test related features for regressions

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
