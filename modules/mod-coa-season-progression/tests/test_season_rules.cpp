// Standalone behavioral tests: g++ -std=c++20 -Wall -Wextra -Werror -I../src
// test_season_rules.cpp ../src/SeasonProtocol.cpp -o /tmp/coa-season-rules
#include "SeasonRules.h"
#include "SeasonProtocol.h"
#include <iostream>
#include <limits>

namespace
{
int failures = 0;
void Check(bool condition, char const* name)
{
    if (!condition)
    {
        std::cerr << "FAIL: " << name << '\n';
        ++failures;
    }
}
bool Same(CoASeason::Account const& a, CoASeason::Account const& b)
{
    return a.progress == b.progress && a.points == b.points && a.earned == b.earned &&
        a.spent == b.spent && a.mask == b.mask;
}
}

int main()
{
    using namespace CoASeason;
    constexpr uint32_t Max = std::numeric_limits<uint32_t>::max();
    Account account{};
    Check(AddProgress(account, 500, DefaultTiers), "multiple tier award accepted");
    Check(account.progress == 500 && account.points == 125 && account.earned == 125 &&
        account.spent == 0 && account.mask == 7, "crossed tiers paid exactly once");
    Check(Reconcile(account, DefaultTiers) && account.points == 125, "reconcile never re-pays claimed tiers");
    account.progress = 50;
    auto changed = DefaultTiers;
    changed[0].threshold = 200;
    Check(Reconcile(account, changed) && account.mask == 7 && account.points == 125,
        "raising thresholds preserves completed tier bits");
    account.progress = 899;
    changed[3].threshold = 899;
    Check(Reconcile(account, changed) && account.points == 215 && account.mask == 15,
        "lowering thresholds awards only newly reached tiers");

    Account overflow{Max, 10, 10, 0, 127};
    Account original = overflow;
    Check(!AddProgress(overflow, 1, DefaultTiers) && Same(overflow, original), "progress overflow is atomic");
    overflow = {99, Max - 24, 0, 0, 0};
    original = overflow;
    Check(!AddProgress(overflow, 1, DefaultTiers) && Same(overflow, original), "point overflow is atomic");
    overflow = {100, 0, Max - 24, 0, 0};
    original = overflow;
    Check(!Reconcile(overflow, DefaultTiers) && Same(overflow, original), "earned overflow is atomic");
    account = {0, 0, 0, 0, 0};
    changed = DefaultTiers;
    changed[1].threshold = changed[0].threshold;
    Check(!AddProgress(account, 500, changed) && account.progress == 0, "invalid thresholds rejected atomically");
    changed = DefaultTiers;
    for (Tier& tier : changed)
        tier.points = Max;
    Account tierValidation{Max, 0, 0, 0, 0};
    Check(!Reconcile(tierValidation, changed), "tier payout sum overflow rejected");

    Check(NewLevels(10, 12) == 2 && NewLevels(12, 10) == 0 && NewLevels(12, 12) == 0,
        "levels respect the persisted high water");
    Check(!LockoutReady(86499, 100, 86400) && LockoutReady(86500, 100, 86400),
        "rolling lockout exact boundary");
    Check(!LockoutReady(99, 100, 0) && LockoutReady(100, 100, 0), "lockout handles clock rollback");
    Check(LockoutReady(std::numeric_limits<uint64_t>::max(), 0, 86400),
        "lockout cannot wrap on large timestamps");

    uint32_t number = 17;
    Check(Number("4294967295", number) && number == Max, "full unsigned boundary");
    for (char const* value : {"", "-1", "+1", " 1", "1 ", "1x", "4294967296", "999999999999999999999"})
    {
        number = 17;
        Check(!Number(value, number) && number == 17, "invalid unsigned leaves output unchanged");
    }
    Check(Number("0", number) && number == 0, "zero accepted");
    int32_t signedNumber = 17;
    Check(SignedNumber("-2147483648", signedNumber) && signedNumber == std::numeric_limits<int32_t>::min(),
        "full signed minimum");
    Check(SignedNumber("2147483647", signedNumber) && signedNumber == std::numeric_limits<int32_t>::max(),
        "full signed maximum");
    for (char const* value : {"", "-", "+1", "2147483648", "-2147483649", "--1", "1.0"})
    {
        signedNumber = 17;
        Check(!SignedNumber(value, signedNumber) && signedNumber == 17, "invalid signed leaves output unchanged");
    }

    Check(Encode("A |%/\xC3\xA9") == "A %7C%25%2F%C3%A9", "text uses bytewise percent encoding");
    std::string decoded = "unchanged";
    Check(Decode("A%7c%25%2f%C3%A9", decoded) && decoded == "A|%/\xC3\xA9",
        "valid encoded UTF-8 including lowercase hex");
    Check(Decode(std::string(64, 'a'), decoded) && decoded.size() == 64, "decoded exact limit accepted");
    for (char const* value : {"%", "%A", "%GG", "%00", "%0A", "%7F", "%C0%AF", "%ED%A0%80"})
    {
        decoded = "unchanged";
        Check(!Decode(value, decoded) && decoded == "unchanged", "malformed or unsafe text rejected atomically");
    }
    Check(!Decode(std::string(65, 'a'), decoded), "decoded length overflow rejected");
    Check(ValidRequestId("aA09_-") && ValidRequestId(std::string(32, 'a')), "safe request ids accepted");
    for (char const* value : {"", "a.b", "a|b", "a b", "a%20b"})
        Check(!ValidRequestId(value), "unsafe request id rejected");
    Check(!ValidRequestId(std::string(33, 'a')), "request id length bounded");

    std::vector<std::string> fields;
    Check(Parse("1|c1|GET", fields) && fields.size() == 3 && fields[2] == "GET", "valid request parsed");
    Check(Parse("1|c1|ADMIN|CREATE|0|A%7CB", fields) && fields.size() == 6 && fields[5] == "A%7CB",
        "parser preserves encoded text fields");
    Check(Parse("1|c1|ADMIN|CREATE|0|", fields) && fields.size() == 6 && fields.back().empty(),
        "parser preserves empty trailing fields for operation validation");
    std::string boundary = "1|c1|ADMIN|" + std::string(234, 'a');
    Check(boundary.size() == 245 && Parse(boundary, fields), "full 255-byte wire boundary accepted");
    Check(!Parse(boundary + "a", fields), "oversized wire rejected");
    for (char const* value : {"2|c1|GET", "1||GET", "1|x.y|GET", "1|c1|get", "1|c1|",
        "1|c1|GET\n", "1|c1|ADMIN|%GG", "1|c1|ADMIN|%00"})
    {
        fields = {"unchanged"};
        Check(!Parse(value, fields) && fields == std::vector<std::string>{"unchanged"},
            "invalid envelope or encoded field rejected atomically");
    }
    Account buyer{500, 100, 125, 25, 7};
    Account before = buyer;
    Check(!Purchase(buyer, 4, 8, 3, 8, 40, 1, false, true) && Same(buyer, before),
        "stale season purchase leaves wallet unchanged");
    Check(!Purchase(buyer, 4, 8, 4, 7, 40, 1, false, true) && Same(buyer, before),
        "stale revision purchase leaves wallet unchanged");
    Check(!Purchase(buyer, 4, 8, 4, 8, 101, 1, false, true) && Same(buyer, before),
        "insufficient funds do not debit");
    Check(!Purchase(buyer, 4, 8, 4, 8, 40, 1, true, true) && Same(buyer, before),
        "owned permanent reward cannot be bought again");
    Check(!Purchase(buyer, 4, 8, 4, 8, 40, 4, false, true) && Same(buyer, before),
        "minimum tier checks permanent completion bit");
    Check(!Purchase(buyer, 4, 8, 4, 8, 40, 1, false, false) && Same(buyer, before),
        "disabled reward cannot debit");
    Check(Purchase(buyer, 4, 8, 4, 8, 40, 1, false, true) &&
        buyer.points == 60 && buyer.spent == 65, "valid purchase debits and records spending");
    before = buyer;
    Check(!Adjust(buyer, -61) && Same(buyer, before), "adjustment cannot underflow");
    Check(Adjust(buyer, -60) && buyer.points == 0 && buyer.spent == 125, "negative adjustment recorded");
    Check(Adjust(buyer, 10) && buyer.points == 10 && buyer.earned == 135, "positive adjustment recorded");
    if (!failures)
        std::cout << "Season rules and protocol tests passed\n";
    return failures ? 1 : 0;
}
