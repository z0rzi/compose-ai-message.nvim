# compose-ai-message.nvim

A simple Neovim plugin to compose AI-friendly markdown messages from code selections or files.

Designed for quickly building up markdown files containing code snippets and comments, perfect for pasting into AI chatbots or issue trackers.

## Features

- 📜 Add visual selections or full buffers as annotated code blocks to a markdown file.
- 📝 Each entry consists of:
  - A user-provided message/description.
  - The code (filename annotated, language-detected codeblock).
- 🔄 Reset the message file instantly.
- 📂 Open the message file in Neovim for review/copying.
- 📋 Copy the markdown file content directly to clipboard.
- ⚡ Works with any filetype.

## Installation

Use your favorite plugin manager. Example for [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'z0rzi/compose-ai-message.nvim',
  config = function()
    require('compose-ai-message').setup()
  end
}
```

Or for [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'z0rzi/compose-ai-message.nvim',
  config = function()
    require('compose-ai-message').setup()
  end
}
```

## Usage

Default key bindings:

| Action                       | Mode    | Default Mapping   | Description                                                    |
|------------------------------|---------|-------------------|----------------------------------------------------------------|
| Add visual selection         | Visual  | `<leader>ma`      | Prompt, then append selection as code block to `.ai-message.md`|
| Add full buffer              | Normal  | `<leader>mb`      | Prompt, then append entire buffer as code block                |
| Reset message file           | Normal  | `<leader>mr`      | Clear all contents of `.ai-message.md`                         |
| Open message file for review | Normal  | `<leader>mo`      | Edit the message file in the current window                    |
| Copy message file to clipboard | Normal  | `<leader>my`      | **Copy all of `.ai-message.md` directly to system clipboard**  |

**Workflow example:**

1. Visually select code (`v`...move).
2. Press `<leader>ma`, describe the code (e.g. "This function sorts input").
3. Repeat as desired!
4. Press `<leader>mo` to open and review your composed markdown, **or** `<leader>my` to copy everything to clipboard.
5. Paste into your AI chatbot or issue tracker!

**Output file format (`.ai-message.md`):**
```markdown
Describe the code selection
(path/to/file.lua)
```lua
-- your code selection here
```

Another comment
(path/to/another_file.py)
```python
# another block of code here
```
```

## Configuration

You may override defaults in your `setup()`:

```lua
require('compose-ai-message').setup{
  file = '/path/to/your.md', -- Where to save the output (default: /tmp/.ai-message.md)
  mappings = {
    reset = '<leader>mr',
    open_file = '<leader>mo',
    add_visual_selection = '<leader>ma',
    add_full_buffer = '<leader>mb',
    copy_file = '<leader>my', -- Copy-to-clipboard mapping
  }
}
```

## FAQ

- **What if I want to use a different output file?**  
  Set the `file` option in your `setup()`!

- **How do I copy everything to the clipboard without opening the file?**  
  Press `<leader>my` (or your configured `copy_file` mapping) in normal mode.

- **What does the output look like?**  
  See the example above—it's ready to copy-paste into ChatGPT or GitHub issues.

## License

MIT
