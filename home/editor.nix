{ pkgs, ... }:

{
  home.sessionVariables.VISUAL = "nvim";

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withPython3 = false;
    withRuby = false;

    initLua = ''
      vim.o.expandtab = true
      vim.o.softtabstop = 2
      vim.o.tabstop = 2
      vim.o.shiftwidth = 2
      vim.o.number = true
      vim.o.ignorecase = true
      vim.o.smartcase = true
      vim.o.cursorline = true
      vim.g.clipboard = "osc52"

      vim.keymap.set("x", "<Tab>", ">gv")
      vim.keymap.set("x", "<S-Tab>", "<gv")
      vim.keymap.set("x", "<C-c>", '"+ygv')

      vim.opt.guicursor:append("i:blinkwait1000-blinkon400-blinkoff400")
    '';

    plugins = [
      {
        plugin = pkgs.vimPlugins.mini-pairs;
        type = "lua";
        config = "require('mini.pairs').setup()";
      }
      {
        plugin = pkgs.vimPlugins.mini-completion;
        type = "lua";
        config = "require('mini.completion').setup()";
      }
      {
        plugin = pkgs.vimPlugins.mini-keymap;
        type = "lua";
        config = ''
          local map_multistep = require('mini.keymap').map_multistep
          map_multistep('i', '<Tab>', { 'pmenu_next' })
          map_multistep('i', '<S-Tab>', { 'pmenu_prev' })
          map_multistep('i', '<CR>', { 'pmenu_accept', 'minipairs_cr' })
          map_multistep('i', '<BS>', { 'minipairs_bs' })
        '';
      }
      {
        plugin = pkgs.vimPlugins.mini-comment;
        type = "lua";
        config = "require('mini.comment').setup()";
      }
      {
        plugin = pkgs.vimPlugins.mini-move;
        type = "lua";
        config = ''
          require('mini.move').setup {
            mappings = {
              left = '<C-S-Left>',
              right = '<C-S-Right>',
              down = '<C-S-Down>',
              up = '<C-S-Up>',
              line_left = '<C-S-Left>',
              line_right = '<C-S-Right>',
              line_down = '<C-S-Down>',
              line_up = '<C-S-Up>',
            },
          }
        '';
      }
      {
        plugin = pkgs.vimPlugins.nvim-treesitter.withPlugins (
          parsers: with parsers; [
            markdown
            markdown_inline
            json
            json5
            yaml
            toml
            kdl
            xml
            properties
            editorconfig
            desktop
            diff
            dockerfile
            caddy
            csv
            git_config
            git_rebase
            gitattributes
            gitcommit
            gitignore
            kconfig
            nginx
            ssh_config

            nix
            lua
            luadoc
            bash
            zsh
            fish
            nu
            powershell
            sql
            promql
            typst
            latex
            bibtex
            cmake
            glsl
            graphql
            helm
            terraform
            jinja

            rust
            python
            java
            kotlin
            scala
            groovy
            html
            htmldjango
            css
            scss
            javascript
            typescript
            vue
            astro
            svelte
            tsx
            ruby
            c
            cpp
            c_sharp
            dart
            elixir
            erlang
            gleam
            go
            gomod
            gosum
            gotmpl
            gpg
            haskell
            julia
            nim
            php
            vala
            zig
          ]
        );
        type = "lua";
        config = ''
          vim.api.nvim_create_autocmd("FileType", {
            callback = function(args)
              if pcall(vim.treesitter.start) then
                local language = vim.treesitter.language.get_lang(args.match)
                if language and language ~= "yaml" and vim.treesitter.query.get(language, "indents") then
                  vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                end
              end
            end,
          })
        '';
      }
      {
        plugin = pkgs.vimPlugins.guess-indent-nvim;
        type = "lua";
        config = "require('guess-indent').setup {}";
      }
      {
        plugin = pkgs.vimPlugins.mini-icons;
        type = "lua";
        config = "require('mini.icons').setup()";
      }
      {
        plugin = pkgs.vimPlugins.mini-git;
        type = "lua";
        config = "require('mini.git').setup()";
      }
      {
        plugin = pkgs.vimPlugins.mini-diff;
        type = "lua";
        config = "require('mini.diff').setup()";
      }
      {
        plugin = pkgs.vimPlugins.mini-statusline;
        type = "lua";
        config = "require('mini.statusline').setup()";
      }
      {
        plugin = pkgs.vimPlugins.kanagawa-nvim;
        type = "lua";
        config = "vim.cmd('colorscheme kanagawa')";
      }
    ];
  };
}
