# Third-party notices

This repository redistributes material from several upstream projects. Keep these
notices if you redistribute or modify the files.

## Shaders

`shaders/cool-retro-frame-amber.hlsl` and `shaders/cool-retro-frame-readable.hlsl`
come from [Chael-Chael/awesome-hermes-eva-skins](https://github.com/Chael-Chael/awesome-hermes-eva-skins)
(MIT, © 2026 Chenyu Zhu), used here unmodified.

`cool-retro-frame-amber.hlsl` is itself based on the Windows Terminal
`samples/PixelShaders/Retro.hlsl` sample and designed for the Windows Terminal pixel
shader setting. The surrounding shader workflow is inspired by:

- [Hammster/windows-terminal-shaders](https://github.com/Hammster/windows-terminal-shaders) — CC0-1.0
- [Microsoft Terminal sample shaders](https://github.com/microsoft/terminal/tree/main/samples/PixelShaders) — MIT

## Colour scheme and profile appearance

The `Cool Retro Amber` scheme values and the profile appearance settings (font face,
size, cursor, antialiasing, opacity) also come from
[Chael-Chael/awesome-hermes-eva-skins](https://github.com/Chael-Chael/awesome-hermes-eva-skins),
MIT, © 2026 Chenyu Zhu.

## Ark Pixel Font

The profiles expect the Ark Pixel 12px monospaced font family from
[TakWolf/ark-pixel-font](https://github.com/TakWolf/ark-pixel-font), released under
the SIL Open Font License 1.1.

The font files are **not** redistributed in this repository. The installer copies
them from a directory you point it at with `-FontSource`; keep the `OFL.txt` that
ships with that release if you pass the files on.
