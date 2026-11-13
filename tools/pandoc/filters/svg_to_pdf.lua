if FORMAT:match 'latex' then
    local function normalize_path(path)
        local parts = {}
        for part in path:gmatch("[^/]+") do
            if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            elseif part ~= "." and part ~= "" then
                table.insert(parts, part)
            end
        end
        return table.concat(parts, "/")
    end

    function Image (elem)
        if elem.src:match("%.svg$") then
            local normalized_path = normalize_path(elem.src)
            elem.src = normalized_path:gsub("%.svg$", ".pdf")
        end
        return elem
    end
end
