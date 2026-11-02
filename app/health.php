<?php
// Health probe target. Returns 200 and "ok" when the app can serve requests.
header('Content-Type: text/plain');
echo "ok\n";