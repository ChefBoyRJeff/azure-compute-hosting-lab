<?php
// P6 M1: minimal page that proves, from outside the app, which code and which slot configuration are live.
//   app_version  : baked into the code; MOVES with a slot swap.
//   slot_setting : from app setting LAB_SLOT, marked "Deployment slot setting" (sticky); STAYS with its slot.
//   instance     : first 8 characters of the App Service instance ID; shows which instance answered (scale-out test).
header('Content-Type: text/plain');

$version = 'v3';

echo "app_version=$version\n";
echo 'slot_setting=' . (getenv('LAB_SLOT') ?: '(not set)') . "\n";
echo 'instance=' . substr(getenv('WEBSITE_INSTANCE_ID') ?: 'unknown', 0, 8) . "\n";
