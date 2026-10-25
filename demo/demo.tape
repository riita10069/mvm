# Records the README demo against a real MicroVM: vhs demo/demo.tape (from the repository root),
# after cloning a sample repo: git clone https://github.com/octocat/Hello-World /tmp/mvm-demo/hello-world
# Waiting for AWS is hidden (fixed, generous sleeps), so the visible timeline and the captions are fixed.
Output demo/raw.mp4
Require zsh
Set Shell zsh
Set FontSize 22
Set Width 1440
Set Height 860
Set Padding 28
Set Theme "Catppuccin Mocha"
Set TypingSpeed 55ms
Set Framerate 24
Set WindowBar Colorful
Set BorderRadius 14
Set Margin 36
Set MarginFill "#8B5CF6"
Env ZDOTDIR "demo/zdotdir"
Env MVM_DEMO_REPO "/tmp/mvm-demo/hello-world"

Hide
Type "source demo/zdotdir/.zshrc"
Enter
Sleep 3s
Show

Sleep 1.5s
Type "mvm "
Sleep 700ms
Tab
Sleep 3s
Enter
Sleep 1s
Enter
Sleep 2.5s
Hide
Sleep 45s
Type "clear"
Enter
Sleep 1s
Show
Sleep 2.5s
Type "uname -sm; claude --version"
Enter
Sleep 2.5s
Type 'claude -p "このリポジトリを日本語で1行で説明して"'
Sleep 500ms
Enter
Hide
Sleep 60s
Show
Sleep 4s
Type "exit"
Enter
Hide
Sleep 3s
Type "clear"
Enter
Sleep 1s
Show
Sleep 1.5s
Type "mvm stop "
Tab
Sleep 2s
Tab
Sleep 3s
Enter
Sleep 2.5s
Hide
Sleep 25s
Type "clear"
Enter
Sleep 1s
Show
Type "mvm hello"
Tab
Sleep 2s
Tab
Sleep 3.5s
Enter
Sleep 800ms
Enter
Hide
Sleep 12s
Type "clear"
Enter
Sleep 1s
Show
Type "mvm ls"
Enter
Sleep 3.5s
Type "mvm rm hello"
Tab
Sleep 2s
Enter
Sleep 2s
Type "y"
Sleep 3s
Type "mvm ls"
Enter
Sleep 4s
