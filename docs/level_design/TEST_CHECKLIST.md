# Antsy Airlines - Level & Gameplay QA Checklist

Status: NOT YET TESTED. Mark PASS or FAIL only after running the build.

| ID | Test case | Expected result | Result |
|----|-----------|-----------------|--------|
| LV-01 | Open level walkthrough preview | Scene loads without missing resources | NOT TESTED |
| LV-02 | Walk on airport apron | Player stays on floor and can turn | NOT TESTED |
| LV-03 | Walk to airplane rear opening | Path is unobstructed | NOT TESTED |
| LV-04 | Walk through passenger aisle | Player can reach cockpit without getting stuck | NOT TESTED |
| LV-05 | Attempt to walk through cabin walls | Player is blocked by collision | NOT TESTED |
| LV-06 | Attempt to walk through passenger seats | Player is blocked by collision | NOT TESTED |
| LV-07 | Walk into interior cargo loading zone | Zone is reachable; visual pad is identifiable | NOT TESTED |
| LV-08 | Inspect four airport spawn markers | All positions are on walkable apron | NOT TESTED |
| LV-09 | Two connected players traverse same aisle | Both can walk and see each other | NOT TESTED - requires team integration |
| LV-10 | Deliver a cargo object to cargo zone | Delivery registers exactly once | NOT TESTED - requires cargo programming |

Bug template: ID / Date / Branch+Commit / Steps to reproduce / Expected / Actual /
Severity / Screenshot or clip / Owner / Retest outcome.
