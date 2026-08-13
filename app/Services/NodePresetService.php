<?php

namespace App\Services;

use App\Models\Server;
use App\Models\ServerMachine;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class NodePresetService
{
    /**
     * WARP 出站占位配置 (sing-box WireGuard 格式)
     */
    private const WARP_OUTBOUND = [
        [
            'tag' => 'warp',
            'type' => 'wireguard',
            'private_key' => 'WARP_SECRET_KEY_PLACEHOLDER',
            'local_address' => [
                '172.16.0.2/32',
                '2606:4700:110:8a36:df92:29f:fe04:1234/128',
            ],
            'peers' => [
                [
                    'public_key' => 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=',
                    'allowed_ips' => ['0.0.0.0/0', '::/0'],
                    'server' => 'engage.cloudflareclient.com',
                    'server_port' => 2408,
                ],
            ],
            'mtu' => 1280,
        ],
    ];

    /**
     * 为 Machine 创建预设节点
     *
     * @param ServerMachine $machine 目标机器
     * @param string $machineName 机器名称（用于节点命名）
     * @param string|null $serverIp 服务器 IP 地址（用于节点 host）
     * @param array|null $groupIds 权限分组 IDs
     * @param array|null $presets 自定义预设选择（null 表示全部 18 种）
     * @param array|null $customPorts 自定义端口映射 ['preset_key' => port]
     * @param array|null $realityKeysInput 外部提供的 Reality 密钥 ['private_key', 'public_key', 'short_id']
     * @param string|null $obfsPasswordInput 外部提供的 OBFS 密码
     * @return int 创建的节点数量
     */
    public static function createPresetNodes(
        ServerMachine $machine,
        string $machineName,
        ?string $serverIp = null,
        ?array $groupIds = null,
        ?array $presets = null,
        ?array $customPorts = null,
        ?array $realityKeysInput = null,
        ?string $obfsPasswordInput = null,
    ): int {
        // 检查该 Machine 是否已有预设节点（防止重复创建）
        $existingCount = Server::where('machine_id', $machine->id)->count();
        if ($existingCount > 0) {
            Log::info("Machine {$machine->id} already has {$existingCount} nodes, skipping preset creation");
            return 0;
        }

        // Reality 密钥: 优先用外部传入，否则自动生成
        if ($realityKeysInput && !empty($realityKeysInput['private_key'])) {
            $realityKeys = $realityKeysInput;
            $shortId = $realityKeysInput['short_id'] ?? bin2hex(random_bytes(4));
        } else {
            $realityKeys = self::generateRealityKeyPair();
            $shortId = bin2hex(random_bytes(4));
        }

        // OBFS 密码: 优先用外部传入
        $obfsPassword = $obfsPasswordInput ?: bin2hex(random_bytes(8));

        // 构建所有预设定义
        $allPresets = self::buildPresetDefinitions($realityKeys, $shortId, $obfsPassword);

        // 如果指定了子集，则过滤
        if ($presets !== null) {
            $allPresets = array_filter($allPresets, fn($key) => in_array($key, $presets), ARRAY_FILTER_USE_KEY);
        }

        // 应用自定义端口
        if ($customPorts !== null) {
            foreach ($customPorts as $presetKey => $port) {
                if (isset($allPresets[$presetKey])) {
                    $allPresets[$presetKey]['port'] = (int) $port;
                    $allPresets[$presetKey]['server_port'] = (int) $port;
                }
            }
        }

        $created = 0;

        DB::transaction(function () use ($allPresets, $machine, $machineName, $serverIp, $groupIds, &$created) {
            $sort = Server::max('sort') ?? 0;

            // 确定节点 host: 优先用传入的 IP，其次从 notes 提取，最后用 machine name
            $host = $serverIp;
            if (empty($host) && $machine->notes) {
                if (preg_match('/IP:\s*([\d.]+)/', $machine->notes, $m)) {
                    $host = $m[1];
                }
            }
            if (empty($host)) {
                $host = $machine->name;
            }

            foreach ($allPresets as $key => $preset) {
                $sort++;

                $serverData = [
                    'type' => $preset['type'],
                    'name' => $machineName . ' | ' . $preset['label'],
                    'host' => $host,
                    'port' => (string) $preset['port'],
                    'server_port' => $preset['server_port'],
                    'protocol_settings' => $preset['protocol_settings'],
                    'machine_id' => $machine->id,
                    'group_ids' => $groupIds,
                    'rate' => 1.0,
                    'show' => false,
                    'enabled' => true,
                    'sort' => $sort,
                    'tags' => $preset['tags'] ?? null,
                ];

                // WARP 出站
                if (!empty($preset['custom_outbounds'])) {
                    $serverData['custom_outbounds'] = $preset['custom_outbounds'];
                }

                Server::create($serverData);
                $created++;
            }
        });

        Log::info("Created {$created} preset nodes for Machine {$machine->id} ({$machineName})");

        return $created;
    }

    /**
     * 构建全部 18 种预设定义
     */
    private static function buildPresetDefinitions(array $realityKeys, string $shortId, string $obfsPassword): array
    {
        $realitySettings = [
            'server_name' => 'www.microsoft.com',
            'server_port' => '443',
            'private_key' => $realityKeys['private_key'],
            'public_key' => $realityKeys['public_key'],
            'short_id' => $shortId,
            'allow_insecure' => false,
        ];

        $defaultMultiplex = [
            'enabled' => false,
            'protocol' => 'yamux',
            'max_connections' => null,
            'padding' => false,
            'brutal' => [
                'enabled' => false,
                'up_mbps' => null,
                'down_mbps' => null,
            ],
        ];

        $defaultUtls = [
            'enabled' => true,
            'fingerprint' => 'chrome',
        ];

        $defaultUtlsDisabled = [
            'enabled' => false,
            'fingerprint' => 'chrome',
        ];

        // ============================================================
        // 直连 9 种
        // ============================================================

        $directPresets = [
            // 1. VLESS Reality (Vision)
            'vless_reality_vision' => [
                'type' => 'vless',
                'label' => 'VLESS Reality',
                'port' => 443,
                'server_port' => 443,
                'tags' => ['Reality', 'Vision'],
                'protocol_settings' => [
                    'tls' => 2,
                    'flow' => 'xtls-rsa-vision',
                    'network' => 'tcp',
                    'network_settings' => null,
                    'tls_settings' => [
                        'server_name' => null,
                        'allow_insecure' => false,
                        'ech' => [
                            'enabled' => false,
                            'config' => null,
                            'query_server_name' => null,
                            'key' => null,
                            'key_path' => null,
                            'config_path' => null,
                        ],
                    ],
                    'reality_settings' => $realitySettings,
                    'encryption' => null,
                    'multiplex' => $defaultMultiplex,
                    'utls' => $defaultUtls,
                ],
            ],

            // 2. VLESS gRPC Reality
            'vless_grpc_reality' => [
                'type' => 'vless',
                'label' => 'VLESS gRPC Reality',
                'port' => 2053,
                'server_port' => 2053,
                'tags' => ['Reality', 'gRPC'],
                'protocol_settings' => [
                    'tls' => 2,
                    'flow' => '',
                    'network' => 'grpc',
                    'network_settings' => ['serviceName' => 'grpc'],
                    'tls_settings' => [
                        'server_name' => null,
                        'allow_insecure' => false,
                        'ech' => [
                            'enabled' => false,
                            'config' => null,
                            'query_server_name' => null,
                            'key' => null,
                            'key_path' => null,
                            'config_path' => null,
                        ],
                    ],
                    'reality_settings' => $realitySettings,
                    'encryption' => null,
                    'multiplex' => $defaultMultiplex,
                    'utls' => $defaultUtls,
                ],
            ],

            // 3. Trojan Reality
            'trojan_reality' => [
                'type' => 'trojan',
                'label' => 'Trojan Reality',
                'port' => 2083,
                'server_port' => 2083,
                'tags' => ['Reality', 'Trojan'],
                'protocol_settings' => [
                    'tls' => 2,
                    'network' => 'tcp',
                    'network_settings' => null,
                    'server_name' => null,
                    'allow_insecure' => false,
                    'tls_settings' => [
                        'server_name' => null,
                        'allow_insecure' => false,
                        'ech' => [
                            'enabled' => false,
                            'config' => null,
                            'query_server_name' => null,
                            'key' => null,
                            'key_path' => null,
                            'config_path' => null,
                        ],
                    ],
                    'reality_settings' => $realitySettings,
                    'multiplex' => $defaultMultiplex,
                    'utls' => $defaultUtls,
                ],
            ],

            // 4. VMess WS
            'vmess_ws' => [
                'type' => 'vmess',
                'label' => 'VMess WS',
                'port' => 8080,
                'server_port' => 8080,
                'tags' => ['VMess', 'WebSocket'],
                'protocol_settings' => [
                    'tls' => 0,
                    'network' => 'ws',
                    'rules' => null,
                    'network_settings' => [
                        'path' => '/ws',
                        'headers' => new \stdClass(),
                    ],
                    'tls_settings' => [
                        'server_name' => null,
                        'allow_insecure' => false,
                        'ech' => [
                            'enabled' => false,
                            'config' => null,
                            'query_server_name' => null,
                            'key' => null,
                            'key_path' => null,
                            'config_path' => null,
                        ],
                    ],
                    'multiplex' => $defaultMultiplex,
                    'utls' => $defaultUtlsDisabled,
                ],
            ],

            // 5. Hysteria2
            'hysteria2' => [
                'type' => 'hysteria',
                'label' => 'Hysteria2',
                'port' => 8443,
                'server_port' => 8443,
                'tags' => ['Hysteria2'],
                'protocol_settings' => [
                    'version' => 2,
                    'bandwidth' => ['up' => null, 'down' => null],
                    'obfs' => [
                        'open' => false,
                        'type' => 'salamander',
                        'password' => null,
                    ],
                    'tls' => [
                        'server_name' => '',
                        'allow_insecure' => true,
                        'ech' => [
                            'enabled' => false,
                            'config' => null,
                            'query_server_name' => null,
                            'key' => null,
                            'key_path' => null,
                            'config_path' => null,
                        ],
                    ],
                    'hop_interval' => null,
                ],
            ],

            // 6. Hysteria2 + OBFS (salamander)
            'hysteria2_obfs' => [
                'type' => 'hysteria',
                'label' => 'Hysteria2 OBFS',
                'port' => 8444,
                'server_port' => 8444,
                'tags' => ['Hysteria2', 'OBFS'],
                'protocol_settings' => [
                    'version' => 2,
                    'bandwidth' => ['up' => null, 'down' => null],
                    'obfs' => [
                        'open' => true,
                        'type' => 'salamander',
                        'password' => $obfsPassword,
                    ],
                    'tls' => [
                        'server_name' => '',
                        'allow_insecure' => true,
                        'ech' => [
                            'enabled' => false,
                            'config' => null,
                            'query_server_name' => null,
                            'key' => null,
                            'key_path' => null,
                            'config_path' => null,
                        ],
                    ],
                    'hop_interval' => null,
                ],
            ],

            // 7. Shadowsocks 2022 (2022-blake3-aes-256-gcm)
            'ss_2022' => [
                'type' => 'shadowsocks',
                'label' => 'SS 2022',
                'port' => 8388,
                'server_port' => 8388,
                'tags' => ['Shadowsocks', '2022'],
                'protocol_settings' => [
                    'cipher' => '2022-blake3-aes-256-gcm',
                    'obfs' => null,
                    'obfs_settings' => null,
                    'plugin' => null,
                    'plugin_opts' => null,
                ],
            ],

            // 8. Shadowsocks Classic (aes-256-gcm)
            'ss_classic' => [
                'type' => 'shadowsocks',
                'label' => 'SS Classic',
                'port' => 8389,
                'server_port' => 8389,
                'tags' => ['Shadowsocks'],
                'protocol_settings' => [
                    'cipher' => 'aes-256-gcm',
                    'obfs' => null,
                    'obfs_settings' => null,
                    'plugin' => null,
                    'plugin_opts' => null,
                ],
            ],

            // 9. TUIC v5
            'tuic_v5' => [
                'type' => 'tuic',
                'label' => 'TUIC v5',
                'port' => 8446,
                'server_port' => 8446,
                'tags' => ['TUIC', 'QUIC'],
                'protocol_settings' => [
                    'version' => 5,
                    'congestion_control' => 'bbr',
                    'alpn' => ['h3'],
                    'udp_relay_mode' => 'native',
                    'tls' => [
                        'server_name' => '',
                        'allow_insecure' => true,
                        'ech' => [
                            'enabled' => false,
                            'config' => null,
                            'query_server_name' => null,
                            'key' => null,
                            'key_path' => null,
                            'config_path' => null,
                        ],
                    ],
                ],
            ],
        ];

        // ============================================================
        // WARP 9 种 — 基于直连节点，修改端口 + 添加 WARP 出站
        // ============================================================

        $warpPortMap = [
            'vless_reality_vision' => 10443,
            'vless_grpc_reality' => 12053,
            'trojan_reality' => 12083,
            'vmess_ws' => 18080,
            'hysteria2' => 18443,
            'hysteria2_obfs' => 18444,
            'ss_2022' => 18388,
            'ss_classic' => 18389,
            'tuic_v5' => 18446,
        ];

        $warpPresets = [];
        foreach ($directPresets as $key => $preset) {
            $warpKey = $key . '_warp';
            $warpPreset = $preset;
            $warpPreset['label'] = $preset['label'] . ' [WARP]';
            $warpPreset['port'] = $warpPortMap[$key];
            $warpPreset['server_port'] = $warpPortMap[$key];
            $warpPreset['tags'] = array_merge($preset['tags'] ?? [], ['WARP']);
            $warpPreset['custom_outbounds'] = self::WARP_OUTBOUND;
            $warpPresets[$warpKey] = $warpPreset;
        }

        return array_merge($directPresets, $warpPresets);
    }

    /**
     * 生成 X25519 密钥对（用于 Reality）
     *
     * @return array ['private_key' => string, 'public_key' => string]
     */
    private static function generateRealityKeyPair(): array
    {
        $keyPair = sodium_crypto_box_keypair();
        $privateKey = sodium_crypto_box_secretkey($keyPair);
        $publicKey = sodium_crypto_scalarmult_base($privateKey);

        return [
            'private_key' => rtrim(strtr(base64_encode($privateKey), '+/', '-_'), '='),
            'public_key' => rtrim(strtr(base64_encode($publicKey), '+/', '-_'), '='),
        ];
    }

    /**
     * 获取所有可用预设的 key 和 label 列表
     */
    public static function getAvailablePresets(): array
    {
        $dummyKeys = self::generateRealityKeyPair();
        $presets = self::buildPresetDefinitions($dummyKeys, '00000000', 'placeholder');

        return collect($presets)->map(fn($p, $key) => [
            'key' => $key,
            'label' => $p['label'],
            'type' => $p['type'],
            'port' => $p['port'],
        ])->values()->toArray();
    }
}
