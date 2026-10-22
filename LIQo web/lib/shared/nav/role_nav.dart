import 'package:flutter/material.dart';

/// One sidebar entry. [path] is the full route path for this role.
class NavItem {
  const NavItem(this.id, this.icon, this.label, this.path, {this.also = const []});

  final String id;
  final IconData icon;
  final String label;
  final String path;

  /// Other path prefixes that belong to this item (detail pages that live elsewhere).
  final List<String> also;
}

/// Everything the shell needs to know about a role.
class RoleNav {
  const RoleNav({
    required this.role,
    required this.name,
    required this.prefix,
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String role;
  final String name;
  final String prefix;
  final String title;
  final String subtitle;
  final List<NavItem> items;

  String get homePath => items.first.path;

  NavItem? itemForPath(String location) {
    for (final item in items) {
      for (final base in [item.path, ...item.also]) {
        if (location == base || location.startsWith('$base/')) return item;
      }
    }
    return null;
  }
}

const _iOverview = Icons.dashboard_outlined;
const _iPerson = Icons.person_outline;
const _iStore = Icons.storefront_outlined;
const _iPin = Icons.location_on_outlined;
const _iChart = Icons.bar_chart;
const _iAudit = Icons.receipt_long_outlined;
const _iSettings = Icons.settings_outlined;
const _iMap = Icons.map_outlined;
const _iAnnounce = Icons.campaign_outlined;
const _iEditor = Icons.architecture;
const _iList = Icons.list_alt_outlined;

const Map<String, RoleNav> roleNavs = {
  'superadmin': RoleNav(
    role: 'superadmin',
    name: 'Superadmin',
    prefix: '/superadmin',
    title: 'Platform overview',
    subtitle: 'Monitor and administer the LIQo platform from one place.',
    items: [
      NavItem('overview', _iOverview, 'Overview', '/superadmin/overview'),
      NavItem('accounts', _iPerson, 'Account management', '/superadmin/accounts'),
      NavItem('profile_requests', Icons.how_to_reg_outlined, 'Profile requests', '/superadmin/profile-requests'),
      NavItem('malls', _iStore, 'Malls & branches', '/superadmin/malls', also: ['/superadmin/branches']),
      NavItem('analytics', _iChart, 'Platform analytics', '/superadmin/analytics'),
      NavItem('audit', _iAudit, 'Audit log', '/superadmin/audit'),
      NavItem('settings', _iSettings, 'Platform settings', '/superadmin/settings'),
      NavItem('account', _iPerson, 'My account', '/superadmin/account'),
    ],
  ),
  'supervisor': RoleNav(
    // Role key stays 'supervisor' in the database and API; people see "Mall owner".
    role: 'supervisor',
    name: 'Mall Owner',
    prefix: '/mall-owner',
    title: 'Owner overview',
    subtitle: 'Track the malls and branches you own.',
    items: [
      NavItem('overview', _iOverview, 'Overview', '/mall-owner/overview'),
      NavItem('malls', _iStore, 'My malls', '/mall-owner/malls'),
      NavItem('branches', _iPin, 'Branches & hours', '/mall-owner/branches'),
      NavItem('stores', _iStore, 'Stores', '/mall-owner/stores'),
      NavItem('admins', _iPerson, 'Mall admins', '/mall-owner/admins'),
      NavItem('maps', _iMap, 'Map viewer', '/mall-owner/maps'),
      NavItem('announcements', _iAnnounce, 'Announcements', '/mall-owner/announcements'),
      NavItem('analytics', _iChart, 'Analytics', '/mall-owner/analytics'),
      NavItem('account', _iPerson, 'My account', '/mall-owner/account'),
    ],
  ),
  'mall_admin': RoleNav(
    role: 'mall_admin',
    name: 'Mall Admin',
    prefix: '/mall-admin',
    title: 'Branch operations',
    subtitle: 'Manage your assigned branches, spaces, stores and visitor information.',
    items: [
      NavItem('overview', _iOverview, 'Overview', '/mall-admin/overview'),
      NavItem('map_editor', _iEditor, 'Map editor', '/mall-admin/map-editor'),
      NavItem('stores', _iStore, 'Stores & spaces', '/mall-admin/stores'),
      NavItem('owners', _iPerson, 'Store owners', '/mall-admin/owners'),
      NavItem('branch', _iPin, 'Branch information', '/mall-admin/branch'),
      NavItem('options', _iList, 'Option lists', '/mall-admin/options'),
      NavItem('announcements', _iAnnounce, 'Announcements', '/mall-admin/announcements'),
      NavItem('analytics', _iChart, 'Analytics', '/mall-admin/analytics'),
      NavItem('account', _iPerson, 'My account', '/mall-admin/account'),
    ],
  ),
  'store_owner': RoleNav(
    role: 'store_owner',
    name: 'Store Owner',
    prefix: '/store-owner',
    title: 'Store workspace',
    subtitle: 'View your assigned stores and submit announcements for review.',
    items: [
      NavItem('overview', _iOverview, 'Overview', '/store-owner/overview'),
      NavItem('my_stores', _iStore, 'My stores', '/store-owner/stores'),
      NavItem('announcements', _iAnnounce, 'Announcements', '/store-owner/announcements'),
      NavItem('account', _iPerson, 'My account', '/store-owner/account'),
    ],
  ),
};

RoleNav navForRole(String role) => roleNavs[role] ?? roleNavs['store_owner']!;
