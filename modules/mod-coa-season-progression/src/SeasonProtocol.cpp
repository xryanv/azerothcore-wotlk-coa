#include "SeasonProtocol.h"
#include <cstdint>
#include <utility>

namespace
{
bool AlphaNumeric(unsigned char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

int Hex(unsigned char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    return -1;
}

bool PrintableUtf8(std::string const& value)
{
    for (std::size_t i = 0; i < value.size();)
    {
        unsigned char first = static_cast<unsigned char>(value[i++]);
        if (first < 0x80)
        {
            if (first < 0x20 || first == 0x7F)
                return false;
            continue;
        }

        unsigned count;
        uint32_t codepoint;
        uint32_t minimum;
        if (first >= 0xC2 && first <= 0xDF)
        {
            count = 1;
            codepoint = first & 0x1F;
            minimum = 0x80;
        }
        else if (first >= 0xE0 && first <= 0xEF)
        {
            count = 2;
            codepoint = first & 0x0F;
            minimum = 0x800;
        }
        else if (first >= 0xF0 && first <= 0xF4)
        {
            count = 3;
            codepoint = first & 0x07;
            minimum = 0x10000;
        }
        else
            return false;

        if (count > value.size() - i)
            return false;
        while (count--)
        {
            unsigned char next = static_cast<unsigned char>(value[i++]);
            if ((next & 0xC0) != 0x80)
                return false;
            codepoint = (codepoint << 6) | (next & 0x3F);
        }
        if (codepoint < minimum || codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
            return false;
    }
    return true;
}
}

namespace CoASeason
{
std::string Encode(std::string const& value)
{
    constexpr char HexDigits[] = "0123456789ABCDEF";
    std::string result;
    for (unsigned char c : value)
    {
        if (AlphaNumeric(c) || c == ' ' || c == '-' || c == '.' || c == '_')
            result.push_back(static_cast<char>(c));
        else
        {
            result.push_back('%');
            result.push_back(HexDigits[c >> 4]);
            result.push_back(HexDigits[c & 0x0F]);
        }
    }
    return result;
}

bool Decode(std::string const& value, std::string& decoded, std::size_t max)
{
    std::string result;
    for (std::size_t i = 0; i < value.size(); ++i)
    {
        unsigned char c = static_cast<unsigned char>(value[i]);
        if (c == '%')
        {
            if (value.size() - i < 3)
                return false;
            int high = Hex(static_cast<unsigned char>(value[i + 1]));
            int low = Hex(static_cast<unsigned char>(value[i + 2]));
            if (high < 0 || low < 0)
                return false;
            c = static_cast<unsigned char>((high << 4) | low);
            i += 2;
        }
        if (result.size() >= max)
            return false;
        result.push_back(static_cast<char>(c));
    }
    if (!PrintableUtf8(result))
        return false;
    decoded = std::move(result);
    return true;
}

bool ValidRequestId(std::string const& value)
{
    if (value.empty() || value.size() > 32)
        return false;
    for (unsigned char c : value)
        if (!AlphaNumeric(c) && c != '_' && c != '-')
            return false;
    return true;
}

bool Parse(std::string const& payload, std::vector<std::string>& fields)
{
    if (payload.size() > MaxPayloadBytes)
        return false;
    for (unsigned char c : payload)
        if (c < 0x20 || c > 0x7E)
            return false;

    std::vector<std::string> result;
    std::size_t start = 0;
    for (;;)
    {
        std::size_t end = payload.find('|', start);
        result.push_back(payload.substr(start, end == std::string::npos ? end : end - start));
        if (end == std::string::npos)
            break;
        start = end + 1;
    }
    if (result.size() < 3 || result[0] != "1" || !ValidRequestId(result[1]) || result[2].empty())
        return false;
    for (char c : result[2])
        if (c < 'A' || c > 'Z')
            return false;
    for (std::size_t i = 3; i < result.size(); ++i)
    {
        std::string decoded;
        if (!Decode(result[i], decoded, MaxPayloadBytes))
            return false;
    }
    fields = std::move(result);
    return true;
}
}
