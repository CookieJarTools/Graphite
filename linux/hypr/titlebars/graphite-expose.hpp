// Reads a private member of Hyprland's: an explicit instantiation may name one (the language's
// own exception), and SExpose hands out a pointer to it. Each use declares a tag with the
// member's type and instantiates SExpose once with the member.
#pragma once

template <typename Tag, typename Tag::type Member>
struct SExpose {
    friend typename Tag::type member(Tag) {
        return Member;
    }
};
