# kinemium-editor

The official editor interface for Kinemium, written entirely in Luau.

This repository contains the UI, tools, panels, and other editor-side functionality that make up the Kinemium Editor. Rather than being compiled directly into the engine, the editor is maintained separately and loaded dynamically at runtime.

When Kinemium starts in editor mode, the engine automatically fetches and caches the appropriate version of this repository, then executes the editor through Kinemium's Luau runtime.

Keeping the editor separate from the engine allows the UI and editor tooling to be updated independently without requiring the entire engine to be rebuilt.
