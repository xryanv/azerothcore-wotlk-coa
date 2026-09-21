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
    return a.points == b.points && a.mask == b.mask;
}
}

int main()
{
    using namespace CoASeason;
    constexpr uint32_t Max = std::numeric_limits<uint32_t>::max();
    Account account{};
    Check(AddPoints(account, 600, DefaultTiers), "multiple tier completion accepted");
    Check(account.points == 600 && account.mask == 7, "crossed tiers are marked exactly once");
    uint32_t newly = NewlyCompleted(Account{}, account);
    Check(newly == 7, "newly completed returns only crossed tier bits");
    Account same = account;
    Check(Reconcile(account, DefaultTiers) && account.points == 600 && account.mask == 7,
        "reconcile never changes cumulative points or repeats completion");
    Check(NewlyCompleted(same, account) == 0, "repeat reconcile has no new tier bits");

    auto changed = DefaultTiers;
    changed = {{{700}, {800}, {900}, {1000}, {1500}, {2200}, {3100}}};
    Check(Reconcile(account, changed) && account.mask == 7 && account.points == 600,
        "raising thresholds preserves completed tier bits");
    changed = DefaultTiers;
    changed[3].threshold = 600;
    Account beforeLower = account;
    Check(Reconcile(account, changed) && account.points == 600 && account.mask == 15,
        "lowering thresholds completes newly satisfied tiers without paying currency");
    Check(NewlyCompleted(beforeLower, account) == 8, "lowered threshold reports one new tier");

    Account overflow{Max, 127};
    Account original = overflow;
    Check(!AddPoints(overflow, 1, DefaultTiers) && Same(overflow, original), "point overflow is atomic");
    account = {};
    changed = DefaultTiers;
    changed[1].threshold = changed[0].threshold;
    Check(!AddPoints(account, 500, changed) && Same(account, Account{}), "invalid thresholds rejected atomically");

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
    Account adjusted{500, 7};
    Check(AdjustPoints(adjusted, -501) == false && adjusted.points == 500 && adjusted.mask == 7,
        "negative GM adjustment cannot underflow or clear completed tiers");
    Check(AdjustPoints(adjusted, -450) && adjusted.points == 50 && adjusted.mask == 7,
        "lowering points preserves completed tier bits");
    Check(AdjustPoints(adjusted, 50) && adjusted.points == 100 && adjusted.mask == 7,
        "positive adjustment changes cumulative points without spending state");
    if (!failures)
        std::cout << "Season rules and protocol tests passed\n";
    return failures ? 1 : 0;
}
