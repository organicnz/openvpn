<?php
declare(strict_types=1);

// Security headers
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('Referrer-Policy: strict-origin-when-cross-origin');
header('Content-Security-Policy: default-src \'self\'; script-src \'self\' \'unsafe-inline\'; style-src \'self\' \'unsafe-inline\'');

// Health check endpoint
if ($_SERVER['REQUEST_URI'] === '/health') {
    http_response_code(200);
    header('Content-Type: application/json');
    echo json_encode([
        'status' => 'healthy',
        'timestamp' => date('c'),
        'service' => 'openvpn-admin'
    ]);
    exit;
}

// Rate limiting (simple implementation)
session_start();
if (!isset($_SESSION['requests'])) {
    $_SESSION['requests'] = [];
}

$now = time();
$_SESSION['requests'] = array_filter($_SESSION['requests'], fn($t) => $now - $t < 300); // 5 min window

if (count($_SESSION['requests']) > 50) { // 50 requests per 5 minutes
    http_response_code(429);
    die('Rate limit exceeded');
}

$_SESSION['requests'][] = $now;

// CSRF token
if (!isset($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// Environment validation - read from secret files
$admin_username = null;
$admin_password = null;

if (isset($_ENV['OPENVPN_ADMIN_USERNAME_FILE']) && file_exists($_ENV['OPENVPN_ADMIN_USERNAME_FILE'])) {
    $admin_username = trim(file_get_contents($_ENV['OPENVPN_ADMIN_USERNAME_FILE']));
} else {
    $admin_username = $_ENV['OPENVPN_ADMIN_USERNAME'] ?? null;
}

if (isset($_ENV['OPENVPN_ADMIN_PASSWORD_FILE']) && file_exists($_ENV['OPENVPN_ADMIN_PASSWORD_FILE'])) {
    $admin_password = trim(file_get_contents($_ENV['OPENVPN_ADMIN_PASSWORD_FILE']));
} else {
    $admin_password = $_ENV['OPENVPN_ADMIN_PASSWORD'] ?? null;
}

if (!$admin_username || !$admin_password || $admin_password === 'changeme') {
    error_log('OpenVPN Admin: Invalid or default credentials detected');
    http_response_code(503);
    die('Service temporarily unavailable');
}

// Authentication with CSRF protection
$error = null;
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!hash_equals($_SESSION['csrf_token'], $_POST['csrf_token'] ?? '')) {
        $error = 'Security token mismatch';
    } elseif (($_POST['username'] ?? '') === $admin_username && 
              ($_POST['password'] ?? '') === $admin_password) {
        $_SESSION['authenticated'] = true;
        $_SESSION['user'] = $admin_username;
        $_SESSION['login_time'] = time();
        header('Location: /');
        exit;
    } else {
        $error = 'Invalid credentials';
        error_log("OpenVPN Admin: Failed login attempt from " . ($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    }
}

// Session timeout (30 minutes)
if (isset($_SESSION['authenticated']) && isset($_SESSION['login_time'])) {
    if (time() - $_SESSION['login_time'] > 1800) {
        session_destroy();
        header('Location: /');
        exit;
    }
}

// Logout
if (($_GET['action'] ?? '') === 'logout') {
    session_destroy();
    header('Location: /');
    exit;
}

// Login form
if (!isset($_SESSION['authenticated'])) {
    ?>
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>OpenVPN Admin Panel</title>
        <style>
            * { box-sizing: border-box; }
            body { 
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                margin: 0; padding: 0; height: 100vh;
                display: flex; align-items: center; justify-content: center;
            }
            .login-container {
                background: white; padding: 2rem; border-radius: 8px;
                box-shadow: 0 10px 25px rgba(0,0,0,0.1); max-width: 400px; width: 100%;
            }
            .logo { text-align: center; margin-bottom: 2rem; color: #333; }
            .form-group { margin: 1rem 0; }
            .form-group label { display: block; margin-bottom: 0.5rem; color: #555; font-weight: 500; }
            .form-group input { 
                width: 100%; padding: 0.75rem; border: 2px solid #e1e5e9;
                border-radius: 4px; font-size: 1rem; transition: border-color 0.3s;
            }
            .form-group input:focus { outline: none; border-color: #667eea; }
            .btn { 
                width: 100%; padding: 0.75rem; background: #667eea; color: white;
                border: none; border-radius: 4px; font-size: 1rem; cursor: pointer;
                transition: background 0.3s;
            }
            .btn:hover { background: #5a6fd8; }
            .error { 
                color: #e74c3c; background: #fdf2f2; padding: 0.75rem;
                border-radius: 4px; margin: 1rem 0; text-align: center;
            }
        </style>
    </head>
    <body>
        <div class="login-container">
            <div class="logo">
                <h2>🔐 OpenVPN Admin</h2>
                <p>Secure Management Portal</p>
            </div>
            
            <?php if ($error): ?>
                <div class="error"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
            <?php endif; ?>
            
            <form method="post">
                <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['csrf_token'], ENT_QUOTES, 'UTF-8') ?>">
                <div class="form-group">
                    <label for="username">Username</label>
                    <input type="text" id="username" name="username" required autocomplete="username">
                </div>
                <div class="form-group">
                    <label for="password">Password</label>
                    <input type="password" id="password" name="password" required autocomplete="current-password">
                </div>
                <button type="submit" class="btn">Sign In</button>
            </form>
        </div>
    </body>
    </html>
    <?php
    exit;
}

// Admin dashboard
$server_status = 'Unknown';
$client_count = 0;

// Try to get actual server status
try {
    if (extension_loaded('sockets')) {
        $socket = @socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
        if ($socket && @socket_connect($socket, 'openvpn-server', 7505)) {
            $server_status = 'Running';
            @socket_close($socket);
        }
    }
} catch (Exception $e) {
    error_log("OpenVPN Admin: Status check failed - " . $e->getMessage());
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenVPN Admin Dashboard</title>
    <style>
        * { box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0; padding: 0; background: #f8f9fa;
        }
        .header { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; padding: 1rem 2rem;
            display: flex; justify-content: space-between; align-items: center;
        }
        .header h1 { margin: 0; }
        .header .user-info { display: flex; align-items: center; gap: 1rem; }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        .card { 
            background: white; border-radius: 8px; padding: 1.5rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 2rem;
        }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 1rem; }
        .status-card { 
            background: white; padding: 1.5rem; border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center;
        }
        .status-card.running { border-left: 4px solid #27ae60; }
        .status-card.warning { border-left: 4px solid #f39c12; }
        .status-card.error { border-left: 4px solid #e74c3c; }
        .btn { 
            padding: 0.5rem 1rem; background: #667eea; color: white;
            border: none; border-radius: 4px; text-decoration: none;
            display: inline-block; transition: background 0.3s;
        }
        .btn:hover { background: #5a6fd8; }
        .btn-danger { background: #e74c3c; }
        .btn-danger:hover { background: #c0392b; }
        pre { background: #2c3e50; color: #ecf0f1; padding: 1rem; border-radius: 4px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔐 OpenVPN Admin Dashboard</h1>
        <div class="user-info">
            <span>Welcome, <?= htmlspecialchars($_SESSION['user'], ENT_QUOTES, 'UTF-8') ?></span>
            <a href="?action=logout" class="btn btn-danger">Logout</a>
        </div>
    </div>
    
    <div class="container">
        <div class="status-grid">
            <div class="status-card <?= $server_status === 'Running' ? 'running' : 'warning' ?>">
                <h3>Server Status</h3>
                <p style="font-size: 1.5rem; margin: 0;">
                    <?= $server_status === 'Running' ? '✅' : '⚠️' ?> <?= htmlspecialchars($server_status, ENT_QUOTES, 'UTF-8') ?>
                </p>
            </div>
            <div class="status-card">
                <h3>Active Clients</h3>
                <p style="font-size: 1.5rem; margin: 0;">👥 <?= $client_count ?></p>
            </div>
            <div class="status-card">
                <h3>Uptime</h3>
                <p style="font-size: 1.5rem; margin: 0;">⏱️ N/A</p>
            </div>
        </div>
        
        <div class="card">
            <h3>Quick Actions</h3>
            <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
                <a href="http://<?= htmlspecialchars($_SERVER['HTTP_HOST'], ENT_QUOTES, 'UTF-8') ?>:8081" target="_blank" class="btn">📊 Status Page</a>
                <a href="/health" class="btn">🏥 Health Check</a>
            </div>
        </div>
        
        <div class="card">
            <h3>Client Management Commands</h3>
            <p>Use these commands via SSH on your server:</p>
            <pre># Create client certificate
docker exec openvpn-server easyrsa build-client-full CLIENT_NAME nopass

# Get client configuration
docker exec openvpn-server ovpn_getclient CLIENT_NAME > CLIENT_NAME.ovpn

# List all clients
docker exec openvpn-server ovpn_listclients

# Revoke client certificate
docker exec openvpn-server ovpn_revokeclient CLIENT_NAME

# Create backup
docker exec openvpn-server /usr/local/bin/backup-certs.sh</pre>
        </div>
    </div>
    
    <script>
        // Auto-refresh status every 30 seconds
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>