def erdos_straus(n, max_x=114514):
    """
    Find positive integers x, y, z such that 4/n = 1/x + 1/y + 1/z.
    Brute-force search with x up to max_x.
    Returns (x, y, z) or None if not found.
    """
    from math import gcd
    target = 4 / n
    # x must be > n/4
    for x in range(n // 4 + 1, max_x + 1):
        if 1/x >= target:
            continue
        # remaining = target - 1/x
        # We need 1/y + 1/z = remaining
        # y must be > 1/remaining, i.e., y > 1/(target - 1/x)
        rem = target - 1/x
        if rem <= 0:
            continue
        # Upper bound for y: we need 2/y >= rem  => y <= 2/rem
        # Lower bound: y > 1/rem
        y_min = int(1 / rem) + 1
        y_max = int(2 / rem) + 1
        for y in range(y_min, min(y_max, max_x) + 1):
            # Compute z from 1/z = rem - 1/y
            inv_z = rem - 1/y
            if inv_z <= 0:
                continue
            # Check if z is integer
            # We can compute z = 1/inv_z and test if near integer
            z = 1 / inv_z
            if abs(z - round(z)) < 1e-9 and round(z) > 0:
                z_int = round(z)
                # Verify exactly
                if abs(4/n - (1/x + 1/y + 1/z_int)) < 1e-12:
                    return (x, y, z_int)
    return None

# Example: find solution for n = 5
n = 5
sol = erdos_straus(n)
if sol:
    x, y, z = sol
    print(f"4/{n} = 1/{x} + 1/{y} + 1/{z}")
    # Check: 4/5 = 0.8, e.g., 1/2 + 1/5 + 1/10 = 0.5+0.2+0.1=0.8
else:
    print("No solution found within bounds.")
