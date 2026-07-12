import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlogtool/models/collaboration_conflict.dart';
import 'package:openlogtool/models/collaboration_dto.dart';
import 'package:openlogtool/providers/collaboration_provider.dart';
import 'package:openlogtool/providers/server_provider.dart';
import 'package:openlogtool/providers/session_provider.dart';
import 'package:openlogtool/services/collaboration_sync.dart';
import 'package:openlogtool/widgets/collaboration_conflict_center.dart';
import 'package:provider/provider.dart';

class CollaborationScreen extends StatefulWidget {
  const CollaborationScreen({super.key});

  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen> {
  final _inviteCodeController = TextEditingController();
  InviteRole _inviteRole = InviteRole.editor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final collaboration = context.read<CollaborationProvider>();
        unawaited(_run(collaboration.refreshCurrentSession));
      }
    });
  }

  @override
  void dispose() {
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('协作会话')),
      body: Consumer3<CollaborationProvider, ServerProvider, SessionProvider>(
        builder: (context, collaboration, server, sessions, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _serverCard(server),
              if (collaboration.progressLabel.isNotEmpty ||
                  collaboration.errorMessage != null ||
                  collaboration.syncErrorMessage != null)
                _statusCard(collaboration),
              if (server.isLoggedIn) _joinCard(collaboration),
              if (sessions.currentSession != null)
                _sessionCard(collaboration, sessions),
              if (collaboration.binding != null &&
                  (collaboration.conflictCount > 0 ||
                      collaboration.conflictsLoading ||
                      collaboration.openConflicts.isNotEmpty))
                CollaborationConflictCenter(
                  conflicts: collaboration.openConflicts,
                  loading: collaboration.conflictsLoading,
                  resolvingConflictId: collaboration.resolvingConflictId,
                  enabled: !collaboration.isBusy &&
                      collaboration.canResolveConflicts,
                  onRefresh:
                      collaboration.isBusy || !collaboration.canResolveConflicts
                          ? null
                          : () => unawaited(
                                _run(collaboration.refreshOpenConflicts),
                              ),
                  onAcceptRemote: (conflictId) => unawaited(
                    _confirmConflictResolution(
                      collaboration,
                      conflictId,
                      CollaborationConflictResolution.useRemote,
                    ),
                  ),
                  onKeepLocal: (conflictId) => unawaited(
                    _confirmConflictResolution(
                      collaboration,
                      conflictId,
                      CollaborationConflictResolution.keepLocal,
                    ),
                  ),
                  onCopyLocalAsNew: (conflictId) => unawaited(
                    _confirmConflictResolution(
                      collaboration,
                      conflictId,
                      CollaborationConflictResolution.copyLocalAsNew,
                    ),
                  ),
                ),
              if (server.isLoggedIn &&
                  collaboration.state == CollaborationState.ready &&
                  collaboration.isOwner) ...[
                if (collaboration.supportsInvites)
                  _inviteManagementCard(collaboration),
                _memberManagementCard(collaboration, server),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _serverCard(ServerProvider server) {
    return Card(
      child: ListTile(
        leading: Icon(
          server.isLoggedIn ? Icons.cloud_done : Icons.cloud_off,
        ),
        title: Text(server.isLoggedIn ? server.username ?? '已登录' : '尚未登录服务器'),
        subtitle: Text(
          server.isLoggedIn
              ? '${server.serverUrl}\n账号 ${server.accountId}'
              : '请先在“设置 → 服务器设置”中检测服务器并登录',
        ),
        isThreeLine: server.isLoggedIn,
      ),
    );
  }

  Widget _statusCard(CollaborationProvider collaboration) {
    final error = collaboration.errorMessage ?? collaboration.syncErrorMessage;
    final errorCode = collaboration.errorMessage != null
        ? collaboration.errorCode
        : collaboration.syncErrorCode;
    return Card(
      color: error == null
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (collaboration.progressLabel.isNotEmpty)
              Text(collaboration.progressLabel),
            if (collaboration.progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: collaboration.progress),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                '${errorCode ?? 'COLLABORATION_FAILED'}\n$error',
              ),
              if (collaboration.remoteCommitPendingLocalApply) ...[
                const SizedBox(height: 8),
                const Text('远端已经提交；客户端只会恢复本地确认，不会重复创建新 mutation。'),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _joinCard(CollaborationProvider collaboration) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('加入协作', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('输入成员邀请码。成功后会以远端相同 Session ID 原子安装本地副本。'),
            const SizedBox(height: 12),
            TextField(
              controller: _inviteCodeController,
              enabled: !collaboration.isBusy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '邀请码',
                hintText: 'ABCDE-12345',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: collaboration.isBusy
                  ? null
                  : () => _run(
                        () => collaboration.joinWithCode(
                          _inviteCodeController.text,
                        ),
                        success: '已加入协作会话',
                      ),
              icon: const Icon(Icons.group_add),
              label: const Text('加入'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionCard(
    CollaborationProvider collaboration,
    SessionProvider sessions,
  ) {
    final session = sessions.currentSession!;
    final binding = collaboration.binding;
    final failedPublish = collaboration.state == CollaborationState.failed &&
        collaboration.failedOperation == 'publish';
    final isLocal = binding == null &&
        collaboration.state != CollaborationState.publishing &&
        !failedPublish;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(session.sessionId),
            const SizedBox(height: 8),
            if (isLocal)
              const Text('本地会话，尚未发布。发布会锁定一致快照并分批上传全部记录。')
            else ...[
              Text(
                '状态 ${collaboration.state.name} · '
                '角色 ${_roleLabel(collaboration.effectiveRole ?? binding?.role)}',
              ),
              const SizedBox(height: 4),
              Text(
                '同步 ${_transportLabel(collaboration.transportPhase)} · '
                '游标 ${collaboration.lastAppliedSeq}/${collaboration.serverHeadSeq}',
              ),
              const SizedBox(height: 4),
              Text(
                '待同步 ${collaboration.pendingCount} · '
                '冲突 ${collaboration.conflictCount} · '
                '拒绝 ${collaboration.rejectedCount}',
              ),
              const SizedBox(height: 4),
              Text(
                collaboration.canEditCurrentSession
                    ? '本地保存后会进入可靠队列，并由规范事件确认同步。'
                    : _readOnlyReason(collaboration, sessions),
              ),
              if (collaboration.lastSuccessfulSyncAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  '最近同步 ${collaboration.lastSuccessfulSyncAt!.toLocal()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (collaboration.hasOpenSessionConflict) ...[
                const SizedBox(height: 8),
                Text(
                  '会话本身存在未解决冲突；请先在冲突中心处理，重命名、关闭和重新打开暂时禁用。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            if (isLocal ||
                collaboration.state == CollaborationState.publishing ||
                failedPublish)
              FilledButton.icon(
                onPressed: collaboration.isBusy
                    ? null
                    : () => _run(
                          collaboration.publishCurrentSession,
                          success: '协作会话发布完成',
                        ),
                icon: const Icon(Icons.cloud_upload),
                label: Text(isLocal ? '发布为协作会话' : '重试发布'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: collaboration.isBusy
                        ? null
                        : () {
                            unawaited(
                              _run(collaboration.refreshCurrentSession),
                            );
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('立即同步并刷新权限'),
                  ),
                  if (collaboration.isOwner) ...[
                    if (session.status == 'active' &&
                        !collaboration.canonicalSessionClosed) ...[
                      OutlinedButton.icon(
                        onPressed: collaboration.isBusy ||
                                collaboration.hasOpenSessionConflict
                            ? null
                            : () =>
                                _renameSession(collaboration, session.title),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('重命名'),
                      ),
                      OutlinedButton.icon(
                        onPressed: collaboration.isBusy ||
                                collaboration.hasOpenSessionConflict
                            ? null
                            : () => _closeSession(collaboration),
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('关闭会话'),
                      ),
                    ] else if (session.status == 'closed' &&
                        collaboration.canonicalSessionClosed)
                      FilledButton.tonalIcon(
                        onPressed: collaboration.isBusy ||
                                collaboration.hasOpenSessionConflict
                            ? null
                            : () => _reopenSession(collaboration),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('重新打开'),
                      ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _transportLabel(CollaborationTransportPhase phase) => switch (phase) {
        CollaborationTransportPhase.stopped => '已停止',
        CollaborationTransportPhase.connecting => '连接中',
        CollaborationTransportPhase.online => '在线',
        CollaborationTransportPhase.backingOff => '等待重连',
        CollaborationTransportPhase.authRequired => '需要登录',
        CollaborationTransportPhase.incompatible => '协议异常',
      };

  String _readOnlyReason(
    CollaborationProvider collaboration,
    SessionProvider sessions,
  ) {
    if (collaboration.state == CollaborationState.revoked) {
      return '成员权限已撤销，本地缓存保持只读。';
    }
    if (sessions.currentSession?.status == 'closed' &&
        !collaboration.canonicalSessionClosed) {
      return '关闭请求已保存到本地，等待同步确认；冲突时将保持锁定。';
    }
    if (sessions.currentSession?.status == 'active' &&
        collaboration.canonicalSessionClosed) {
      return '重新打开请求已保存到本地，服务器确认前保持只读。';
    }
    if (sessions.currentSession?.status != 'active') {
      return '协作会话已关闭，本地缓存保持只读。';
    }
    if (collaboration.effectiveRole == SessionRole.viewer) {
      return '当前账号是只读成员。';
    }
    if (collaboration.state == CollaborationState.resyncing) {
      return '事件游标需要重装规范快照；待同步修改仍保留。';
    }
    return '正在确认权限与事件游标，暂时保持只读。';
  }

  Future<void> _renameSession(
    CollaborationProvider collaboration,
    String currentTitle,
  ) async {
    final controller = TextEditingController(text: currentTitle);
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('重命名协作会话'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 200,
            decoration: const InputDecoration(labelText: '会话标题'),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('保存到本地'),
            ),
          ],
        ),
      );
      if (title == null || title == currentTitle) return;
      await _run(
        () => collaboration.renameCurrentSession(title),
        success: '标题已保存到本地，等待同步确认',
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _closeSession(CollaborationProvider collaboration) async {
    final accepted = await _confirm(
      '关闭协作会话',
      '关闭后所有成员都不能继续添加或修改记录；Owner 可以稍后重新打开。',
    );
    if (!accepted) return;
    await _run(
      collaboration.closeCurrentSession,
      success: '会话已在本地关闭，等待同步确认',
    );
  }

  Future<void> _reopenSession(CollaborationProvider collaboration) async {
    final accepted = await _confirm(
      '重新打开协作会话',
      '重新打开会作为一项同步修改提交；服务器确认前仍保持只读。',
    );
    if (!accepted) return;
    await _run(
      collaboration.reopenCurrentSession,
      success: '重新打开请求已保存到本地，等待同步确认',
    );
  }

  Future<void> _confirmConflictResolution(
    CollaborationProvider collaboration,
    String conflictId,
    CollaborationConflictResolution resolution,
  ) async {
    final title = switch (resolution) {
      CollaborationConflictResolution.useRemote => '采用远端版本',
      CollaborationConflictResolution.keepLocal => '保留本地版本',
      CollaborationConflictResolution.copyLocalAsNew => '复制为新日志',
    };
    final message = switch (resolution) {
      CollaborationConflictResolution.useRemote =>
        '本地未同步修改会被远端规范版本替换，此操作不会再次提交 mutation。',
      CollaborationConflictResolution.keepLocal =>
        '将基于最新远端版本创建一个新的 mutation。若远端再次变化，仍可能产生新冲突。',
      CollaborationConflictResolution.copyLocalAsNew =>
        '远端原日志会保留，本地内容将使用新的日志 ID 创建副本并重新同步。',
    };
    final accepted = await _confirm(
      title,
      message,
    );
    if (!accepted || !mounted) return;
    final action = switch (resolution) {
      CollaborationConflictResolution.useRemote => () =>
          collaboration.useRemoteForConflict(conflictId),
      CollaborationConflictResolution.keepLocal => () =>
          collaboration.keepLocalForConflict(conflictId),
      CollaborationConflictResolution.copyLocalAsNew => () =>
          collaboration.copyLocalAsNewForConflict(conflictId),
    };
    final success = switch (resolution) {
      CollaborationConflictResolution.useRemote => '已采用远端版本',
      CollaborationConflictResolution.keepLocal => '已保留本地版本并进入重试队列',
      CollaborationConflictResolution.copyLocalAsNew => '已复制为新日志并进入同步队列',
    };
    await _run(
      action,
      success: success,
    );
  }

  Widget _inviteManagementCard(CollaborationProvider collaboration) {
    final secret = collaboration.lastCreatedInvite;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '成员邀请',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DropdownButton<InviteRole>(
                  value: _inviteRole,
                  items: const [
                    DropdownMenuItem(
                      value: InviteRole.editor,
                      child: Text('编辑者'),
                    ),
                    DropdownMenuItem(
                      value: InviteRole.viewer,
                      child: Text('只读成员'),
                    ),
                  ],
                  onChanged: collaboration.isBusy
                      ? null
                      : (value) => setState(() => _inviteRole = value!),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: collaboration.isBusy
                      ? null
                      : () => _run(
                            () => collaboration.createInvite(role: _inviteRole),
                            success: '邀请码已生成',
                          ),
                  child: const Text('生成'),
                ),
              ],
            ),
            if (secret?.code != null) ...[
              const SizedBox(height: 12),
              Text('邀请码只在本次创建响应中显示：',
                  style: Theme.of(context).textTheme.bodySmall),
              SelectableText(
                secret!.code!,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
            const Divider(height: 24),
            if (collaboration.invites.isEmpty)
              const Text('暂无邀请')
            else
              ...collaboration.invites.map(
                (invite) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${invite.role == InviteRole.editor ? '编辑者' : '只读成员'} '
                    '••${invite.codeHint}',
                  ),
                  subtitle: Text(
                    '${invite.usedCount}/${invite.maxUses} 次 · '
                    '${invite.revokedAt == null ? '有效至 ${invite.expiresAt.toLocal()}' : '已撤销'}',
                  ),
                  trailing: invite.revokedAt == null
                      ? IconButton(
                          tooltip: '撤销',
                          onPressed: collaboration.isBusy
                              ? null
                              : () => _run(
                                    () => collaboration.revokeInvite(
                                      invite.inviteId,
                                    ),
                                  ),
                          icon: const Icon(Icons.block),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _memberManagementCard(
    CollaborationProvider collaboration,
    ServerProvider server,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('成员', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...collaboration.members.map(
              (member) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  member.role == SessionRole.owner
                      ? Icons.workspace_premium
                      : Icons.person,
                ),
                title: Text(member.username ?? member.userId),
                subtitle: Text(_roleLabel(member.role)),
                trailing: member.userId == server.accountId
                    ? const Text('当前账号')
                    : PopupMenuButton<String>(
                        enabled: !collaboration.isBusy,
                        onSelected: (action) {
                          if (action == 'owner') {
                            _confirmTransfer(collaboration, member);
                          } else if (action == 'remove') {
                            _confirmRemove(collaboration, member);
                          } else if (action == 'editor') {
                            _run(
                              () => collaboration.updateMemberRole(
                                member.userId,
                                InviteRole.editor,
                              ),
                              success: '成员已设为编辑者',
                            );
                          } else if (action == 'viewer') {
                            _run(
                              () => collaboration.updateMemberRole(
                                member.userId,
                                InviteRole.viewer,
                              ),
                              success: '成员已设为只读',
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'editor',
                            child: Text('设为编辑者'),
                          ),
                          PopupMenuItem(
                            value: 'viewer',
                            child: Text('设为只读成员'),
                          ),
                          PopupMenuItem(
                            value: 'owner',
                            child: Text('转移所有权'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('移除成员'),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTransfer(
    CollaborationProvider collaboration,
    MembershipDto member,
  ) async {
    final accepted = await _confirm(
      '转移所有权',
      '转移给 ${member.username ?? member.userId} 后，你将变为编辑者。',
    );
    if (accepted) {
      await _run(
        () => collaboration.transferOwnership(member.userId),
        success: '所有权已转移',
      );
    }
  }

  Future<void> _confirmRemove(
    CollaborationProvider collaboration,
    MembershipDto member,
  ) async {
    final accepted = await _confirm(
      '移除成员',
      '确定移除 ${member.username ?? member.userId}？权限会立即失效。',
    );
    if (accepted) {
      await _run(
        () => collaboration.removeMember(member.userId),
        success: '成员已移除',
      );
    }
  }

  Future<bool> _confirm(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _run(
    Future<Object?> Function() operation, {
    String? success,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await operation();
      if (mounted && success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('操作失败: $error')));
      }
    }
  }

  String _roleLabel(SessionRole? role) => switch (role) {
        SessionRole.owner => '所有者',
        SessionRole.editor => '编辑者',
        SessionRole.viewer => '只读成员',
        null => '未知',
      };
}
