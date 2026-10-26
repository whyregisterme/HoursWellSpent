# imports/

Script headers this mod compiles against but never ships.

- `Magelight.psc`: the Papyrus API of [Magelight UI](https://github.com/Severause/MagelightUI) by
  Severause, MIT (`Magelight-LICENSE.txt`), taken from `papyrus/Magelight.psc` at commit
  `dc903542c656`. Magelight installs its own `Magelight.pex`. Shipping one here would overwrite it,
  so the build stages nothing from this folder and the release check refuses a `Magelight.pex`.
