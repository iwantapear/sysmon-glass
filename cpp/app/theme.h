// Palettes and materials, copied value-for-value from modules/Theme.ps1 so the
// C++ build renders identically. Colors are 0xAARRGGBB.
#pragma once
#include <string>
#include <vector>
#include <cstdint>

namespace theme {

struct Palette {
    const char* id;
    uint32_t bg[3];
    uint32_t card[3];
    uint32_t rim[3];
    uint32_t gloss;
    uint32_t reflection;
    uint32_t text;
    uint32_t secondary;
    uint32_t muted;
    uint32_t label;
    uint32_t pillBg;
    uint32_t pillBorder;
    uint32_t buttonBg;
    uint32_t adjustButton;
    uint32_t local;
    uint32_t remote;
    uint32_t glowTop;
    uint32_t glowBottom;
    uint32_t shadow;
    float shadowOpacity;
    uint32_t track;
    uint32_t warn;
    uint32_t bad;
};

// dark / light are the authored ones; the nine custom palettes override a subset
// of the dark palette (Theme.ps1 clones dark and replaces the listed keys).
inline std::vector<Palette> BuildAll() {
    Palette dark{
        "dark",
        { 0xB01A2C50u, 0xA81C4A68u, 0x98202C82u },
        { 0xDC38607Au, 0xC0284E60u, 0xD42C6A70u },
        { 0x8FBFD5EEu, 0x4D8DAFCDu, 0x3F7797B7u },
        0x27C4DDFFu, 0x1B95C5FFu,
        0xFFF5F9FFu, 0xFFE1ECF8u, 0xFFB6CADFu, 0xFFE5F0FCu,
        0x7044617Eu, 0x68B9D9EEu, 0x5449697Cu, 0xF336536Du,
        0xFF86C9FFu, 0xFF83E7DDu, 0x4B76AFFFu, 0x3676E7DAu,
        0x050D1C, 0.42f, 0x558AA1BCu, 0xFFFFD77Cu, 0xFFFF8D91u
    };
    Palette light{
        "light",
        { 0xA8DCEEFFu, 0xB8C8F4FFu, 0xE0D0F0FFu },
        { 0xF9FBFDFFu, 0xE4F0FAFFu, 0xF0E8FAFFu },
        { 0xF9FFFFFFu, 0xA8BECFE4u, 0x83A7BED7u },
        0x82FFFFFFu, 0x65FFFFFFu,
        0xFF19334Fu, 0xFF45617Eu, 0xFF6A829Bu, 0xFF3B5874u,
        0x96F5FBFFu, 0x8CAECDE4u, 0x8CEEFFFFu, 0xF2E5F2FDu,
        0xFF2478C2u, 0xFF137E7Cu, 0x55C3ABFFu, 0x558DE5DBu,
        0x536E9B, 0.27f, 0x5099B5CFu, 0xFF9B5600u, 0xFFB92338u
    };

    struct Override {
        const char* id;
        uint32_t bg[3]; uint32_t card[3]; uint32_t rim[3];
        uint32_t gloss, reflection, local, remote, glowTop, glowBottom, pillBg, buttonBg, adjustButton;
        // a few palettes also override text tokens; nullptr means "keep dark"
        const uint32_t* text; const uint32_t* secondary; const uint32_t* muted; const uint32_t* label;
    };
    static const uint32_t forestText = 0xFFF2FFF7u, forestMuted = 0xFFC0D7C8u, forestSecondary = 0xFFE0EFE4u, forestLabel = 0xFFE4F6EAu;
    static const uint32_t amberText = 0xFFFFFAEFu, amberMuted = 0xFFE0C8B6u, amberSecondary = 0xFFF4E3D5u, amberLabel = 0xFFF5E8DCu;

    const Override overrides[] = {
        { "sunset", { 0xD06B2C6Eu, 0xC89A3A78u, 0xBE3C5C82u }, { 0xE0B05878u, 0xCA884860u, 0xD8A04070u }, { 0xA8FFE0C8u, 0x68FFC8A8u, 0x58E09888u },
          0x38FFE2B8u, 0x2BFFC890u, 0xFFFFD9A8u, 0xFFFFB8A0u, 0x4AFF9E60u, 0x4AFF6E9Au, 0x8DA04A66u, 0x83A05870u, 0xF3B05A6Eu, nullptr, nullptr, nullptr, nullptr },
        { "rose", { 0xD0A0306Au, 0xC8B84872u, 0xBE902878u }, { 0xE0C86880u, 0xCAB05868u, 0xD8B8607Au }, { 0xA8FFD8F0u, 0x60E8B8D8u, 0x50D098C0u },
          0x35FFE8F5u, 0x28FFD0E0u, 0xFFFFD0E8u, 0xFFFFC8B8u, 0x4AFF90B8u, 0x3AFF6898u, 0x8DC04878u, 0x83C05888u, 0xF3D05A88u, nullptr, nullptr, nullptr, nullptr },
        { "violet", { 0xD04A2C8Eu, 0xC43A4494u, 0xB8526C9Au }, { 0xE05A4498u, 0xCA48387Eu, 0xD8546C90u }, { 0xA8D0E8FFu, 0x5890C8E0u, 0x4870A8C8u },
          0x30B8D8FFu, 0x2488A8F5u, 0xFFC8A8FFu, 0xFF8FC8FFu, 0x4A8860FFu, 0x3A48D8E8u, 0x8D483088u, 0x82385292u, 0xF35A3A80u, nullptr, nullptr, nullptr, nullptr },
        { "aurora", { 0xD0146858u, 0xBA1C7074u, 0xC82A9882u }, { 0xDE14705Eu, 0xC810604Cu, 0xD4208064u }, { 0x9AF0E0D8u, 0x58C8D8B0u, 0x4890B898u },
          0x2EF0F0D0u, 0x22C0E0C0u, 0xFF8FFFE0u, 0xFFC0A8FFu, 0x4040FFA0u, 0x35B060E0u, 0x8D186850u, 0x80207058u, 0xF330A880u, nullptr, nullptr, nullptr, nullptr },
        { "neon", { 0xD007081Cu, 0xB60C0C26u, 0xC0101832u }, { 0xDC141438u, 0xC60C0C30u, 0xD8183048u }, { 0xA800F0FFu, 0x48E8A0E0u, 0x38C080C8u },
          0x3020F0FFu, 0x2410C0FFu, 0xFF00E5FFu, 0xFFFF40C8u, 0x3B00C8FFu, 0x30FF30C8u, 0x8D101848u, 0x82182850u, 0xF300E5A0u, nullptr, nullptr, nullptr, nullptr },
        { "flame", { 0xD0A81622u, 0xBC981830u, 0xC8A82038u }, { 0xE0C22030u, 0xCAA01824u, 0xD5B02030u }, { 0xA8FFD0D0u, 0x60F0A0B0u, 0x50D08898u },
          0x32FFD0C0u, 0x28FFA890u, 0xFFFFB8A8u, 0xFFFFD8B0u, 0x45FF8050u, 0x38E04040u, 0x8DA02030u, 0x82B02838u, 0xF3E04A50u, nullptr, nullptr, nullptr, nullptr },
        { "ocean", { 0xD01A2E55u, 0xB11C4270u, 0xC117344Bu }, { 0xE0294A75u, 0xCC203653u, 0xDC1F4260u }, { 0x9AB2D7FFu, 0x5486B5E5u, 0x4885BACEu },
          0x309CC6FFu, 0x236CE7FFu, 0xFF95CFFFu, 0xFF83EDD9u, 0x596686FFu, 0x4279E6DFu, 0x8D285C86u, 0x82416991u, 0xF32A527Du, nullptr, nullptr, nullptr, nullptr },
        { "forest", { 0xD019392Fu, 0xBA254A3Eu, 0xC616342Bu }, { 0xE035584Bu, 0xCD233F37u, 0xD3274B3Eu }, { 0xA6C8E9D4u, 0x5E83B9A5u, 0x4885A99Bu },
          0x2FB1ECD4u, 0x226FFFC1u, 0xFF9DE6C3u, 0xFFDCF0ABu, 0x4E73CDA7u, 0x375CBE97u, 0x88476C54u, 0x80507762u, 0xF33B6351u,
          &forestText, &forestSecondary, &forestMuted, &forestLabel },
        { "amber", { 0xD04C3028u, 0xB755382Du, 0xC2402B2Du }, { 0xE06C4D3Fu, 0xCF48342Eu, 0xDB4D3836u }, { 0xA5EBD0AFu, 0x619E7A66u, 0x568E6A6Bu },
          0x32FFD6A2u, 0x2BFFA974u, 0xFFFFCC91u, 0xFFF4B9AFu, 0x56DC9B5Bu, 0x48CC7770u, 0x886C4C3Cu, 0x88765547u, 0xF36D4C3Au,
          &amberText, &amberSecondary, &amberMuted, &amberLabel }
    };

    std::vector<Palette> all;
    all.push_back(light);
    all.push_back(dark);
    for (const auto& o : overrides) {
        Palette p = dark;
        p.id = o.id;
        for (int i = 0; i < 3; ++i) { p.bg[i] = o.bg[i]; p.card[i] = o.card[i]; p.rim[i] = o.rim[i]; }
        p.gloss = o.gloss; p.reflection = o.reflection;
        p.local = o.local; p.remote = o.remote;
        p.glowTop = o.glowTop; p.glowBottom = o.glowBottom;
        p.pillBg = o.pillBg; p.buttonBg = o.buttonBg; p.adjustButton = o.adjustButton;
        if (o.text) p.text = *o.text;
        if (o.secondary) p.secondary = *o.secondary;
        if (o.muted) p.muted = *o.muted;
        if (o.label) p.label = *o.label;
        all.push_back(p);
    }
    return all;
}

// Theme order used by the tray/context menus (matches $script:themeOrder).
inline std::vector<std::string> Order() {
    return { "light", "dark", "sunset", "rose", "violet", "aurora", "neon", "flame", "ocean", "forest", "amber" };
}

inline const Palette& Get(const std::vector<Palette>& all, const std::string& id) {
    for (const auto& p : all) if (id == p.id) return p;
    return all[1];   // dark, same fallback as Palettes.Get
}

// Material modes scale the palette's authored card alpha, exactly like
// modules/Material.ps1 (0.62 / 0.88 / 1.00 plus gloss 0.45 / 0.20 / 0).
struct Material { float scale; float gloss; const char* id; };
inline Material GetMaterial(const std::string& id) {
    if (id == "frosted") return { 0.88f, 0.20f, "frosted" };
    if (id == "solid") return { 1.00f, 0.00f, "solid" };
    return { 0.62f, 0.45f, "glass" };
}

} // namespace theme
