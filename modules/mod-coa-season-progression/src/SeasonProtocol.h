#ifndef COA_SEASON_PROTOCOL_H
#define COA_SEASON_PROTOCOL_H

#include <cstddef>
#include <string>
#include <vector>

namespace CoASeason
{
inline constexpr std::size_t MaxPayloadBytes = 245;

std::string Encode(std::string const& value);
// Decodes printable UTF-8, rejects controls/malformed UTF-8, bounds decoded byte length.
// Output arguments are unchanged on failure.
bool Decode(std::string const& value, std::string& decoded, std::size_t max = 64);
bool ValidRequestId(std::string const& value);
// Parses the version/id/operation envelope. Text fields remain encoded.
// Operation-specific arity, numeric fields, authorization and revisions belong to the service.
bool Parse(std::string const& payload, std::vector<std::string>& fields);
}

#endif
