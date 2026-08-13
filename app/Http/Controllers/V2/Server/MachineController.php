<?php

namespace App\Http\Controllers\V2\Server;

use App\Http\Controllers\Controller;
use App\Models\Server;
use App\Models\ServerMachine;
use App\Models\ServerMachineLoadHistory;
use App\Services\NodePresetService;
use App\Services\ServerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * machine controller
 */
class MachineController extends Controller
{
    /**
     * get nodes list for machine
     */
    public function nodes(Request $request): JsonResponse
    {
        $machine = $this->authenticateMachine($request);

        $nodes = ServerService::getMachineNodes($machine)
            ->map(fn($node) => [
                'id' => $node->id,
                'type' => $node->type,
                'name' => $node->name,
            ])->values();

        return response()->json([
            'nodes' => $nodes,
            'base_config' => [
                'push_interval' => (int) admin_setting('server_push_interval', 60),
                'pull_interval' => (int) admin_setting('server_pull_interval', 60),
            ],
        ]);
    }

    /**
     * report machine status
     */
    public function status(Request $request): JsonResponse
    {
        $request->validate([
            'cpu' => 'required|numeric|min:0|max:100',
            'mem.total' => 'required|integer|min:0',
            'mem.used' => 'required|integer|min:0',
            'swap.total' => 'nullable|integer|min:0',
            'swap.used' => 'nullable|integer|min:0',
            'disk.total' => 'nullable|integer|min:0',
            'disk.used' => 'nullable|integer|min:0',
            'net.in_speed' => 'nullable|numeric|min:0',
            'net.out_speed' => 'nullable|numeric|min:0',
        ]);

        $machine = $this->authenticateMachine($request);
        $recordedAt = now()->timestamp;

        $loadStatus = [
            'cpu' => (float) $request->input('cpu'),
            'mem' => [
                'total' => (int) $request->input('mem.total'),
                'used' => (int) $request->input('mem.used'),
            ],
            'swap' => [
                'total' => (int) $request->input('swap.total', 0),
                'used' => (int) $request->input('swap.used', 0),
            ],
            'disk' => [
                'total' => (int) $request->input('disk.total', 0),
                'used' => (int) $request->input('disk.used', 0),
            ],
            'updated_at' => $recordedAt,
        ];

        $netInSpeed = $request->input('net.in_speed');
        $netOutSpeed = $request->input('net.out_speed');

        if ($netInSpeed !== null && $netOutSpeed !== null) {
            $loadStatus['net'] = [
                'in_speed' => (float) $netInSpeed,
                'out_speed' => (float) $netOutSpeed,
            ];
        }

        $machine->forceFill([
            'load_status' => $loadStatus,
            'last_seen_at' => $recordedAt,
        ])->save();

        $historyData = [
            'machine_id' => $machine->id,
            'cpu' => (float) $request->input('cpu'),
            'mem_total' => (int) $request->input('mem.total'),
            'mem_used' => (int) $request->input('mem.used'),
            'disk_total' => (int) $request->input('disk.total', 0),
            'disk_used' => (int) $request->input('disk.used', 0),
            'recorded_at' => $recordedAt,
        ];

        if ($netInSpeed !== null && $netOutSpeed !== null) {
            $historyData['net_in_speed'] = (float) $netInSpeed;
            $historyData['net_out_speed'] = (float) $netOutSpeed;
        }

        ServerMachineLoadHistory::create($historyData);

        // Time-based cleanup: keep 24h of data, runs on ~5% of requests
        if (random_int(1, 20) === 1) {
            ServerMachineLoadHistory::query()
                ->where('machine_id', $machine->id)
                ->where('recorded_at', '<', now()->subDay()->timestamp)
                ->delete();
        }

        return response()->json(['data' => true]);
    }

    /**
     * 安装脚本调用：自动创建预设节点
     */
    public function autoSetup(Request $request): JsonResponse
    {
        $machine = $this->authenticateMachine($request);

        $request->validate([
            'server_ip' => 'nullable|string',
            'group_ids' => 'nullable|array',
            'setup_presets' => 'nullable|array',
        ]);

        // 确保 server_token 已设置（xboard-node 调用 server/user 需要）
        $currentToken = admin_setting('server_token');
        if (empty($currentToken)) {
            \DB::table('v2_settings')->updateOrInsert(
                ['name' => 'server_token'],
                [
                    'value' => $request->input('token'),
                    'group' => 'server',
                    'type' => 'input',
                ]
            );
            \Log::info("Auto-set server_token from machine token during autoSetup");
        }

        // 如果提供了服务器 IP，更新机器名称中记录
        $serverIp = $request->input('server_ip');
        if ($serverIp) {
            $machine->forceFill(['notes' => ($machine->notes ? $machine->notes . "\n" : '') . 'IP: ' . $serverIp])->saveQuietly();
        }

        // 检查是否已有节点
        $existingNodes = Server::where('machine_id', $machine->id)->count();

        $nodesCreated = NodePresetService::createPresetNodes(
            $machine,
            $machine->name,
            $request->input('group_ids'),
            $request->input('setup_presets')
        );

        // 返回当前机器的全部节点列表
        $allNodes = Server::where('machine_id', $machine->id)
            ->get(['id', 'name', 'type', 'port', 'server_port', 'show', 'enabled'])
            ->toArray();

        return response()->json([
            'data' => [
                'nodes_created' => $nodesCreated,
                'existing_nodes' => $existingNodes,
                'total_nodes' => count($allNodes),
                'nodes' => $allNodes,
            ],
        ]);
    }

    private function authenticateMachine(Request $request): ServerMachine
    {
        $request->validate([
            'machine_id' => 'required|integer',
            'token' => 'required|string',
        ]);

        $machine = ServerMachine::where('id', $request->input('machine_id'))
            ->where('token', $request->input('token'))
            ->first();

        if (!$machine || !$machine->is_active) {
            abort(403, 'Machine not found or disabled');
        }

        $machine->forceFill(['last_seen_at' => now()->timestamp])->saveQuietly();

        return $machine;
    }
}
