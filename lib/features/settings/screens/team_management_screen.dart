import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/models/business_member.dart';
import '../../../data/models/business_invitation.dart';
import '../../../data/repositories/app_repository.dart';

class TeamManagementScreen extends StatefulWidget {
  final AppRepository repository;

  const TeamManagementScreen({super.key, required this.repository});

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<BusinessMember> _members = [];
  List<BusinessInvitation> _invitations = [];

  bool get _isAdminOrOwner =>
      widget.repository.isBusinessAdmin || widget.repository.isBusinessOwner;

  @override
  void initState() {
    super.initState();
    _loadTeamData();
  }

  Future<void> _loadTeamData() async {
    final activeBiz = widget.repository.activeBusiness;
    if (activeBiz == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No active business selected.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final membersFuture = widget.repository.backendClient.getBusinessMembers(
        businessId: activeBiz.businessId,
        token: widget.repository.authToken,
      );

      final invitationsFuture = _isAdminOrOwner
          ? widget.repository.backendClient.getBusinessInvitations(
              businessId: activeBiz.businessId,
              token: widget.repository.authToken,
            )
          : Future.value(<BusinessInvitation>[]);

      final results = await Future.wait([membersFuture, invitationsFuture]);

      if (mounted) {
        setState(() {
          _members = results[0] as List<BusinessMember>;
          _invitations = results[1] as List<BusinessInvitation>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load team: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _showInviteDialog() {
    final emailCtrl = TextEditingController();
    String selectedRole = 'staff';
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.person_add_alt_1_rounded, color: AppColors.primarySage),
              SizedBox(width: 8),
              Text('Invite Team Member', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Send an email invitation with a secure 7-day token to join this business.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Work Email Address',
                    hintText: 'colleague@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required';
                    if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Permitted Role',
                    prefixIcon: Icon(Icons.security_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'staff',
                      child: Text('Staff (Send & View Operations)'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Admin (Full Management & Templates)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedRole = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primarySage,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isSubmitting = true);

                      final res = await widget.repository.backendClient.inviteBusinessMember(
                        email: emailCtrl.text.trim(),
                        role: selectedRole,
                        businessId: widget.repository.activeBusinessId,
                        token: widget.repository.authToken,
                      );

                      if (!ctx.mounted) return;
                      Navigator.pop(dialogCtx);
                      if (!mounted) return;

                      if (res['success'] == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✓ Invitation sent to ${emailCtrl.text.trim()}'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        _loadTeamData();
                      } else {
                        final errMsg = res['error']?['message'] ?? 'Failed to send invitation';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $errMsg'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send Invitation'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangeRoleDialog(BusinessMember member) {
    if (member.isOwner && !widget.repository.isBusinessOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only business owners can modify owner privileges.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    String newRole = member.role;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Change Role for ${member.displayName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Role: ${member.role.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: newRole == 'owner' ? 'admin' : newRole,
                decoration: const InputDecoration(labelText: 'New Role'),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => newRole = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySage, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final res = await widget.repository.backendClient.updateMemberRole(
                  userId: member.userId,
                  role: newRole,
                  businessId: widget.repository.activeBusinessId,
                  token: widget.repository.authToken,
                );

                if (!mounted) return;
                if (res['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✓ Updated ${member.displayName} to $newRole'), backgroundColor: AppColors.success),
                  );
                  _loadTeamData();
                } else {
                  final err = res['error']?['message'] ?? 'Failed to update role';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $err'), backgroundColor: AppColors.error),
                  );
                }
              },
              child: const Text('Update Role'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemoveMember(BusinessMember member) {
    if (member.isOwner) {
      final ownerCount = _members.where((m) => m.isOwner).length;
      if (ownerCount <= 1) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cannot Remove Owner'),
            content: const Text(
              'This member is the only Owner of the business. You must promote another member to Owner before removing them.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        return;
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: Text(
          'Are you sure you want to revoke ${member.displayName}\'s access to this business? They will no longer be able to view campaigns, customers, or send messages.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final res = await widget.repository.backendClient.removeBusinessMember(
                userId: member.userId,
                businessId: widget.repository.activeBusinessId,
                token: widget.repository.authToken,
              );

              if (!mounted) return;
              if (res['success'] == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✓ Removed ${member.displayName} from business'), backgroundColor: AppColors.success),
                );
                _loadTeamData();
              } else {
                final err = res['error']?['message'] ?? 'Failed to remove member';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $err'), backgroundColor: AppColors.error),
                );
              }
            },
            child: const Text('Remove Member'),
          ),
        ],
      ),
    );
  }

  void _confirmRevokeInvitation(BusinessInvitation inv) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Revoke Invitation?'),
        content: Text('Are you sure you want to revoke the pending invitation for ${inv.email}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              final success = await widget.repository.backendClient.revokeBusinessInvitation(
                invitationId: inv.id,
                businessId: widget.repository.activeBusinessId,
                token: widget.repository.authToken,
              );

              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✓ Revoked invitation for ${inv.email}'), backgroundColor: AppColors.success),
                );
                _loadTeamData();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to revoke invitation'), backgroundColor: AppColors.error),
                );
              }
            },
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    Color bg;
    Color fg;
    String label = role.toUpperCase();

    switch (role.toLowerCase()) {
      case 'owner':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        break;
      case 'admin':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeBiz = widget.repository.activeBusiness;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Management'),
        actions: [
          if (_isAdminOrOwner)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Invite Member',
              onPressed: _showInviteDialog,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadTeamData,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadTeamData,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadTeamData,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      children: [
                        // Business Identity Banner
                        AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySageContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.business_rounded, color: AppColors.primarySageDark, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activeBiz?.displayName ?? 'Business Team',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Your Role: ${(activeBiz?.role ?? "staff").toUpperCase()}',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              _buildRoleBadge(activeBiz?.role ?? 'staff'),
                            ],
                          ),
                        ),

                        if (!_isAdminOrOwner) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textMuted),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Team management and invitations are restricted to administrators and owners.',
                                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Section 1: Active Members Roster
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Active Members (${_members.length})',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            if (_isAdminOrOwner)
                              TextButton.icon(
                                onPressed: _showInviteDialog,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Invite', style: TextStyle(fontSize: 12.5)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (_members.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('No team members found.', style: TextStyle(color: AppColors.textMuted)),
                            ),
                          )
                        else
                          ...List.generate(_members.length, (idx) {
                            final m = _members[idx];
                            final isMe = m.userId == widget.repository.currentUser?.id;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: isDark ? AppColors.borderDark : const Color(0xFFE2E8F0)),
                              ),
                              elevation: 0,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primarySageContainer,
                                  foregroundColor: AppColors.primarySageDark,
                                  child: Text(
                                    (m.name != null && m.name!.isNotEmpty)
                                        ? m.name![0].toUpperCase()
                                        : (m.email != null && m.email!.isNotEmpty ? m.email![0].toUpperCase() : 'U'),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        m.displayName + (isMe ? ' (You)' : ''),
                                        style: TextStyle(
                                          fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    _buildRoleBadge(m.role),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (m.email != null)
                                      Text(m.email!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                    if (m.joinedAt != null)
                                      Text(
                                        'Joined: ${m.joinedAt!.year}-${m.joinedAt!.month.toString().padLeft(2, '0')}-${m.joinedAt!.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                      ),
                                  ],
                                ),
                                trailing: _isAdminOrOwner && !isMe
                                    ? PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert_rounded, size: 20),
                                        onSelected: (val) {
                                          if (val == 'change_role') {
                                            _showChangeRoleDialog(m);
                                          } else if (val == 'remove') {
                                            _confirmRemoveMember(m);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'change_role',
                                            child: Row(
                                              children: [
                                                Icon(Icons.badge_outlined, size: 16),
                                                SizedBox(width: 8),
                                                Text('Change Role'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Row(
                                              children: [
                                                Icon(Icons.person_remove_outlined, size: 16, color: AppColors.error),
                                                SizedBox(width: 8),
                                                Text('Remove Member', style: TextStyle(color: AppColors.error)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          }),

                        // Section 2: Pending Invitations
                        if (_isAdminOrOwner) ...[
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Pending Invitations (${_invitations.length})',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_invitations.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Center(
                                child: Text('No pending invitations.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                              ),
                            )
                          else
                            ...List.generate(_invitations.length, (idx) {
                              final inv = _invitations[idx];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: isDark ? AppColors.borderDark : const Color(0xFFE2E8F0)),
                                ),
                                elevation: 0,
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFFFEF3C7),
                                    foregroundColor: Color(0xFFB45309),
                                    child: Icon(Icons.mail_outline_rounded, size: 20),
                                  ),
                                  title: Text(inv.email, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                  subtitle: Text(
                                    'Role: ${inv.role.toUpperCase()} · ${inv.isExpired ? "Expired" : "Pending 7-day token"}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: inv.isExpired ? AppColors.error : AppColors.textMuted,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.cancel_outlined, color: AppColors.error, size: 20),
                                    tooltip: 'Revoke Invitation',
                                    onPressed: () => _confirmRevokeInvitation(inv),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}
