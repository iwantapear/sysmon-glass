#pragma once

#include "config.h"

#include <algorithm>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace layout {
constexpr int kColumns = 4;
constexpr int kRows = 12;
using Slots = std::map<std::string, cfg::Slot>;

struct Card { std::string key; int span; };

inline bool Overlaps(cfg::Slot a, int aSpan, cfg::Slot b, int bSpan) {
    return a.row == b.row && a.column < b.column + bSpan && b.column < a.column + aSpan;
}

inline bool CanPlace(const Slots& slots, const std::vector<Card>& cards, const Card& card,
                     cfg::Slot slot, int columns = kColumns) {
    if (slot.row < 0 || slot.row >= kRows || slot.column < 0 || slot.column > columns - card.span)
        return false;
    for (const auto& other : cards) {
        auto position = slots.find(other.key);
        if (other.key != card.key && position != slots.end() &&
            Overlaps(slot, card.span, position->second, other.span)) return false;
    }
    return true;
}

inline bool PlaceFirst(Slots& slots, const std::vector<Card>& cards, const Card& card, int columns) {
    for (int i = 0; i < kRows * columns; ++i) {
        const cfg::Slot slot{i / columns, i % columns};
        if (CanPlace(slots, cards, card, slot, columns)) {
            slots[card.key] = slot;
            return true;
        }
    }
    return false;
}

inline Slots Pack(const std::vector<Card>& cards, const Slots& saved, int columns = kColumns) {
    Slots result;
    for (const auto& card : cards) {
        auto slot = saved.find(card.key);
        if (slot != saved.end() && CanPlace(result, cards, card, slot->second, columns))
            result.emplace(card.key, slot->second);
    }
    for (const auto& card : cards) {
        if (!result.contains(card.key)) PlaceFirst(result, cards, card, columns);
    }
    if (!saved.empty() && result.size() != cards.size()) return Pack(cards, {}, columns);
    return result;
}

inline bool Move(Slots& slots, const std::vector<Card>& cards, const Card& card,
                 cfg::Slot target, bool freePlacement) {
    int lastRow = -1;
    for (const auto& [key, slot] : slots) {
        if (key != card.key) lastRow = std::max(lastRow, slot.row);
    }
    if ((!freePlacement && target.row > lastRow + 1) ||
        !CanPlace({}, cards, card, target)) return false;

    Slots moved = slots;
    std::vector<Card> displaced;
    for (const auto& other : cards) {
        auto slot = moved.find(other.key);
        if (other.key != card.key && slot != moved.end() &&
            Overlaps(target, card.span, slot->second, other.span)) {
            displaced.push_back(other);
            moved.erase(slot);
        }
    }
    moved[card.key] = target;
    for (const auto& other : displaced) {
        if (!PlaceFirst(moved, cards, other, kColumns)) return false;
    }
    slots = std::move(moved);
    return true;
}
} // namespace layout
