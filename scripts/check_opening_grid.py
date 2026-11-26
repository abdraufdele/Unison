# SPDX-License-Identifier: MIT
"""Independent integer oracle for the C1 Forge grid digests and selected feed vectors."""
from bisect import bisect_left
from hashlib import sha256

SPACING = 60
LIMIT = 887220
TARGET_SCALE = 10**10
PRECISION = 10**90


# Certify each scaled grid price with directed rational bounds.
def gridFloors():
    # Advance one whole grid step at a time with its exact rational numerator/denominator.
    # Round both endpoints outward at 90 decimal places, then certify each integer bin.
    prices = {0: TARGET_SCALE}
    for sign, num, den in [(1, 10001**60, 10000**60), (-1, 10000**60, 10001**60)]:
        lo = hi = PRECISION
        for tick in range(SPACING, LIMIT + 1, SPACING):
            lo = lo * num // den
            hi = -(-hi * num // den)
            lower = lo * TARGET_SCALE // PRECISION
            upper = hi * TARGET_SCALE // PRECISION
            assert lower == upper, sign * tick
            prices[sign * tick] = lower
    return prices


# Print independent grid digests and adversarial neighboring feed vectors.
def main():
    prices = gridFloors()
    for start, stop in [(-LIMIT, -60), (0, 443580), (443640, LIMIT)]:
        words = b"".join(prices[t].to_bytes(32, "big") for t in range(start, stop + 1, SPACING))
        print(start, stop, len(words) // 32, sha256(words).hexdigest())

    ticks = sorted(prices)
    floors = [prices[t] for t in ticks]
    assert floors == sorted(floors)
    max_answer = prices[LIMIT] // 101
    print("Maximum feed answer", max_answer)
    # Neither percentage target can equal a grid price for a positive C1 answer.
    answers = [1, 10**6, 10**8, 125_000_000, max_answer - 1, max_answer]
    for t in (-600, 0, 600):
        for percent in (99, 101):
            below = prices[t] // percent
            answers.extend([below, below + 1])
    for answer in answers:
        lower = ticks[bisect_left(floors, 99 * answer) - 1]
        upper = ticks[bisect_left(floors, 101 * answer)]
        assert 0 < upper - lower <= 480
        print(answer, lower, upper)


if __name__ == "__main__":
    main()
