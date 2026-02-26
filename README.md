# Godot Shader Previewer

A real-time variable inspector and visual debugger for Godot shaders.
Adds the visual shader node preview feature in the code editor.

[![Addon Preview](https://raw.githubusercontent.com/cashew-olddew/godot-shader-previewer/main/meta/preview.mp4)](https://raw.githubusercontent.com/cashew-olddew/godot-shader-previewer/main/meta/preview.mp4)

## Features

- **Line-by-Line Inspection** - Instantly preview the value of any variable at the cursor's current line in the fragment shader.
- **Live Uniform Sync** - Automatically detects and mirrors the uniform values from the selected node in your scene.
- **Different datatype support** - Supports `bool`, `int`, `float`, `vec2`, `vec3`, and `vec4` for immediate visual feedback in the editor.
- **Multiline support** - Works even if the selected assignment is on multiple lines

---

## Usage Guide

1. **Enable the Plugin**: Navigate to `Project Settings > Plugins` and enable **Shader Previewer**.
2. **Select an Active Node**: Select a node in your scene that is already using the shader you want to preview. This allows the plugin to copy your current uniform settings (like colors or textures).
3. **Open the Shader**: Open the `.gdshader` file in the Godot Shader Editor.
4. **Debug a Line**: Place your cursor on any line inside the `fragment()` function that assigns a value (e.g., `float mask = ...;`).
5. **Observe Results**: The **Shader Preview** dock will show the visual state of that variable at that exact point in the code execution.

---

## Known Issues

1. When shaders have errors, the editor prints them in the Output panel. Since this addon is generating new shaders based on the initial shader (which could have errors mid-writing, for example), it will also produce the same errors, resulting in the output showing the same error twice.
2. When editing a shader while a node is selected, the addon tries to see if the shader matches the shader used in that node's material. Since the addon's shader is never going to be 1:1 equivalent to the node shader, it only checks for the shader uniforms to match. This addresses most cases, but could lead to false positives when two shaders have the same uniforms.
3. Currently there's no public API for getting the Shader Editor, so the addon uses a hacky way to get the editor instance. This could break in future versions of Godot if the internal structure of the editor changes.

## Contributing

If you find any bugs or improvement ideas, feel free to [fork](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo#about-forks) this repository and suggest a change.

If you'd like to see an improvement, but don't know how to contribute, you can [create an Issue](https://github.com/cashew-olddew/godot-shader-line-previewer/issues/new).

## License

This project falls under the [CC0](LICENSE) license, meaning that you can do anything you want with the code here, even use it commercially. You do not have any obligation to credit me, but doing so would be highly appreciated.

## Support

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/H2H2XSCXW)

Donations are appreciated and help me continue creating free content. Please donate only what you can afford. 🥜
