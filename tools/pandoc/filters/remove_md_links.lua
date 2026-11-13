function Link(el)
    if string.match(el.target, "%.md$") or string.match(el.target, "%.md#") then
        return el.content
    else
        return el
    end
end
