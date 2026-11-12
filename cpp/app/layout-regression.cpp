#include "layout.h"
#include <cassert>
#include <iostream>
#include <random>

int main() {
    const std::vector<layout::Card> cards{{"a", 2}, {"b", 1}, {"c", 1}, {"d", 2}};
    auto slots = layout::Pack(cards, {{"a", {1, 1}}, {"b", {1, 2}}, {"d", {4, 3}}});
    assert(slots.size() == cards.size());
    assert(slots.at("a").row == 1 && slots.at("a").column == 1);
    assert(layout::Move(slots, cards, cards[0], {0, 1}, false));
    assert(slots.at("a").row == 0 && slots.at("a").column == 1);
    assert(!layout::Move(slots, cards, cards[0], {11, 0}, false));
    assert(layout::Move(slots, cards, cards[0], {11, 0}, true));
    assert(!layout::Move(slots, cards, cards[0], {11, 3}, true));

    std::mt19937 random(19);
    for (int trial = 0; trial < 5000; ++trial) {
        std::vector<layout::Card> catalog;
        layout::Slots saved;
        for (int index = 0; index < 23; ++index) {
            const auto key = std::to_string(index);
            catalog.push_back({key, 1 + int(random() % 2)});
            saved[key] = {int(random() % 15) - 1, int(random() % 6) - 1};
        }
        const auto packed = layout::Pack(catalog, saved);
        assert(packed.size() == catalog.size());
        for (const auto& card : catalog)
            assert(layout::CanPlace(packed, catalog, card, packed.at(card.key)));
    }

    std::vector<layout::Card> longCards;
    layout::Slots fragmented;
    for (int index = 0; index < 23; ++index) {
        const auto key = std::to_string(index);
        longCards.push_back({key, 2});
        if (index < 12) fragmented[key] = {index, 1};
    }
    assert(layout::Pack(longCards, fragmented).size() == longCards.size());
    std::cout << "Layout regression passed (5000 randomized layouts)\n";
}
