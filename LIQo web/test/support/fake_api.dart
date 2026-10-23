// A fake HTTP layer for widget tests: every page gets realistic rows with long
// names, so layout problems show up without a server.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:gabay_admin/features/map_editor/map_models.dart';

const longName = 'Ayala Center Cebu Business Park Annex and Terraces Extension Wing';
const longEmail = 'a.very.long.person.name.for.layout.testing@example-mall-company.com';
const longPerson = 'Maria Consolacion De Los Santos-Villanueva';

Map<String, dynamic> paged(List<Map<String, dynamic>> items) => {'items': items, 'totalCount': items.length, 'page': 1, 'pageSize': 20};

Map<String, dynamic> userJson({int id = 1, String role = 'superadmin'}) => {
      'id': id,
      'email': longEmail,
      'fullName': longPerson,
      'role': role,
      'isActive': true,
      'mustChangePassword': false,
      'lastLoginAt': '2026-10-21T08:00:00',
      'createdAt': '2026-10-01T08:00:00',
      'access': {'malls': 1, 'branches': 2, 'stores': 0},
      'reportsTo': null,
    };

Map<String, dynamic> sampleReport(int days) => {
      'days': days,
      'activity': {
        'days': [
          for (var i = 0; i < days; i++)
            {
              'date': '2026-${((i ~/ 28) % 12 + 1).toString().padLeft(2, '0')}-${(i % 28 + 1).toString().padLeft(2, '0')}',
              'logins': i % 5,
              'submitted': i % 2,
              'published': 1,
              'mapPublications': i % 7 == 0 ? 1 : 0,
              'mapEdits': 2,
              'failedLogins': i % 3,
              'lockouts': 0,
            },
        ],
        'totals': {'logins': 40, 'submitted': 3, 'published': days, 'mapPublications': 2, 'mapEdits': 2 * days, 'failedLogins': 9, 'lockouts': 1},
        'previous': {'logins': 12, 'submitted': 5, 'published': 1, 'mapPublications': 0, 'mapEdits': 3, 'failedLogins': 2, 'lockouts': 0},
      },
      'stores': {
        'byCategory': [
          {'name': 'Apparel and Fashion Accessories for the Whole Family', 'count': 12},
          {'name': 'Food', 'count': 7},
          {'name': 'No category', 'count': 3},
        ],
        'byBranch': [
          {'branchId': 1, 'branch': longName, 'mall': 'SM Prime Holdings Incorporated', 'active': 14, 'inactive': 3, 'withOwner': 9, 'linked': 4},
          {'branchId': 2, 'branch': 'Robinsons Galleria', 'mall': 'Robinsons', 'active': 8, 'inactive': 0, 'withOwner': 8, 'linked': 8},
        ],
      },
      'accounts': {
        'byRole': [
          {'role': 'superadmin', 'total': 2, 'active': 2, 'inactive': 0, 'unassigned': 0, 'tempPassword': 1, 'locked': 0},
          {'role': 'supervisor', 'total': 3, 'active': 2, 'inactive': 1, 'unassigned': 1, 'tempPassword': 0, 'locked': 1},
          {'role': 'mall_admin', 'total': 5, 'active': 5, 'inactive': 0, 'unassigned': 2, 'tempPassword': 2, 'locked': 0},
          {'role': 'store_owner', 'total': 9, 'active': 7, 'inactive': 2, 'unassigned': 0, 'tempPassword': 3, 'locked': 0},
        ],
      },
      'announcements': {
        'byStatus': {'pending': 4, 'approved': 12, 'rejected': 2},
        'byTimeState': {'live': 5, 'upcoming': 3, 'expired': 4},
        'bySource': [
          {'role': 'supervisor', 'count': 3},
          {'role': 'mall_admin', 'count': 9},
          {'role': 'store_owner', 'count': 6},
        ],
        'byBranch': [
          {'branchId': 1, 'branch': longName, 'mall': 'SM Prime', 'live': 3, 'pending': 2, 'total': 11},
        ],
        'pending': [
          {
            'id': 9,
            'title': 'Grand Anniversary Mega Sale with Extended Mall Hours and Live Performances',
            'role': 'store_owner',
            'author': longPerson,
            'store': 'Northline Apparel Flagship Boutique',
            'branches': '$longName, Robinsons Galleria',
            'createdAt': '2026-10-15T08:00:00',
            'waitingDays': 6,
          },
        ],
        'decided': 7,
        'avgDecisionDays': 1.4,
      },
      'maps': {
        'summary': {'none': 1, 'draft': 1, 'published': 1},
        'byBranch': [
          {'branchId': 1, 'branch': longName, 'mall': 'SM Prime', 'state': 'published', 'versions': 5, 'publishedVersion': 5, 'publishedAt': '2026-10-21T10:00:00', 'publishedBy': longPerson, 'spaces': 48, 'named': 31, 'linked': 12},
          {'branchId': 2, 'branch': 'Robinsons Galleria', 'mall': 'Robinsons', 'state': 'draft', 'versions': 0, 'spaces': 0, 'named': 0, 'linked': 0},
          {'branchId': 3, 'branch': 'Festival Mall', 'mall': 'Filinvest', 'state': 'none', 'versions': 0, 'spaces': 0, 'named': 0, 'linked': 0},
        ],
      },
      'security': {
        'topFailures': [
          {'email': longEmail, 'count': 7},
          {'email': 'short@x.y', 'count': 2},
        ],
      },
      'note': 'Shopper traffic, map views and searches are not available yet: no shopper app is connected.',
    };

Map<String, dynamic> mallPeopleJson() => {
      'mall': {'id': 1, 'name': 'SM Prime Holdings Incorporated Shopping Centers Division', 'logoUrl': null, 'isActive': true, 'branchCount': 12},
      'owners': [
        {'id': 2, 'fullName': longPerson, 'email': longEmail, 'isActive': true, 'wholeMall': true, 'branchNames': ''},
        {'id': 5, 'fullName': 'Branch Level Owner', 'email': 'b@x.y', 'isActive': false, 'wholeMall': false, 'branchNames': '$longName, Galleria'},
      ],
      'admins': [
        {
          'id': 3,
          'fullName': 'Admin With A Very Long Name Indeed',
          'email': longEmail,
          'isActive': true,
          'mustChangePassword': true,
          'reportsTo': {'id': 2, 'name': longPerson},
          'branches': [
            {'id': 1, 'name': longName},
            {'id': 2, 'name': 'Galleria'},
          ],
        },
        {
          'id': 4,
          'fullName': 'Unowned Admin',
          'email': 'u@x.y',
          'isActive': true,
          'mustChangePassword': false,
          'reportsTo': null,
          'branches': [
            {'id': 1, 'name': 'Short'},
          ],
        },
      ],
    };

Map<String, dynamic> profileRequestJson({int id = 1}) => {
      'id': id,
      'userId': 3,
      'role': 'mall_admin',
      'userActive': true,
      'current': {'fullName': longPerson, 'email': longEmail},
      'requested': {'fullName': 'Maria Consolacion Santos', 'email': 'maria.santos.new.address@example-mall-company.com'},
      'status': 'pending',
      'reason': null,
      'reviewedBy': null,
      'reviewedAt': null,
      'createdAt': '2026-10-21T09:30:00',
    };

/// Answers every request the admin pages make with canned JSON.
class FakeApiAdapter implements HttpClientAdapter {
  FakeApiAdapter({
    this.role = 'superadmin',
    this.hang = false,
    this.hangWhen,
    this.mapLocked = false,
    this.sharedAnnouncement = false,
    this.inactiveBranch = false,
    this.aiConfigured = true,
    this.aiModel = 'gemini-2.5-pro-vision-preview-long-model-name',
    this.aiBlocked = false,
    this.aiScaleFound,
    this.aiWallet,
    this.aiMine = (12.5, 20),
    this.creditRequestPending = false,
    this.creditsAvgCost = 0.5,
  });

  /// Round 19: a mall admin's own credits (balance, last top-up).
  final (double balance, double? full) aiMine;

  /// The mall admin has a credit request waiting.
  final bool creditRequestPending;

  /// The average paid reading lately (the low-balance warning).
  final double? creditsAvgCost;

  /// The wallet's balance and its last top-up (the credit bar), when a test sets them.
  final (double balance, double full)? aiWallet;

  /// Round 18: the reading also found the plan's scale from a written dimension.
  final Map<String, Object>? aiScaleFound;

  /// The gateway wallet refuses readings (empty), with the gateway's own reason.
  final bool aiBlocked;

  /// AI reading (Round 15): the server has a gateway key, and the chosen model (null = none yet).
  final bool aiConfigured;
  final String? aiModel;

  /// Plans uploaded in this test (Round 16), listed back like the server does.
  final List<Map<String, dynamic>> uploadedBackdrops = [];

  /// Writes the app made (POST/PUT/DELETE), with their bodies, in order.
  final List<(String method, String path, Object? data)> writes = [];

  /// Announcement 1 also reaches branches outside the viewer's scope (Round 14).
  final bool sharedAnnouncement;

  /// Branch pages show an inactive branch (Round 14).
  final bool inactiveBranch;

  /// The '/maps' list reports branch 1's map as being edited (for the release-lock button).
  final bool mapLocked;

  final String role;

  /// Never answer: every page stays in its loading state.
  final bool hang;

  /// Never answer the requests whose path matches, so a page shows a mix of
  /// loaded and loading modules (what a slow network produces).
  final RegExp? hangWhen;
  final List<String> requests = [];

  /// Branch 1 has no map until someone creates it (POST /maps/1).
  bool mapCreated = false;

  /// GET /maps/:id: the branch "Mall B · Branch Example", with or without its map.
  Map<String, dynamic> _mapBundle() => {
        'branch': {'id': 1, 'name': 'Branch Example', 'mallName': 'Mall B'},
        'map': mapCreated
            ? {
                'id': 1,
                'draft': LayoutDoc(buildings: [
                  Building(id: 'bd-1', name: 'Main building', levels: [Level(id: 'lv-1', name: 'Ground floor')]),
                ]).toJson(),
                'draftVersion': 1,
                'publishedVersion': null,
                'lock': null,
              }
            : null,
        'versions': const [],
        'storeLinks': const [],
        'warnings': const [],
        // Like the server: mall admins and superadmins may create and edit maps.
        'canEdit': role == 'mall_admin' || role == 'superadmin',
      };

  static const _catalog = {
    'version': 1,
    'categories': <String>[],
    'features': <String, dynamic>{},
    'spaceTypes': <String>[],
    'wallKinds': <String>[],
    'openingKinds': <String>[],
    'connectorKinds': <String>[],
    'oneWayCapable': <String>[],
  };

  /// An uploaded plan as the server describes it (Round 16). Drawings (svg, dxf,
  /// dwg) come back as PNGs; a DXF/DWG named with "nounit" does not say its unit.
  static Map<String, dynamic> backdropJson(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final kind = const {'svg', 'dxf', 'dwg'}.contains(ext) ? ext : 'image';
    final cad = kind == 'dxf' || kind == 'dwg';
    final noUnit = cad && name.contains('nounit');
    return {
      'id': 'abcdef0123456789abcdef0123456789',
      'branchId': 1,
      'originalName': name,
      'mimeType': 'image/png',
      'width': 1000,
      'height': 600,
      'uploadedAt': '2026-10-22T08:00:00',
      'kind': kind,
      'units': cad && !noUnit ? 'mm' : null,
      'mpp': cad && !noUnit ? 0.02 : null,
      'needsUnit': noUnit,
    };
  }

  /// POST .../convert: a reading of a 20 × 14 m plan, with an unsure room and a store match.
  static Map<String, dynamic> aiProposal({String levelId = 'lv-1', double credits = 0.75}) => {
        'proposal': {
          'levelId': levelId,
          'walls': [
            {'id': 'ai-w-1', 'a': [2, 2], 'b': [18, 2], 't': 0.3, 'kind': 'boundary'},
            {'id': 'ai-w-2', 'a': [18, 2], 'b': [18, 12], 't': 0.3, 'kind': 'boundary'},
            {'id': 'ai-w-3', 'a': [2, 12], 'b': [18, 12], 't': 0.3, 'kind': 'boundary'},
            {'id': 'ai-w-4', 'a': [2, 2], 'b': [2, 12], 't': 0.3, 'kind': 'boundary'},
            {'id': 'ai-w-5', 'a': [10, 2], 'b': [10, 12], 't': 0.1, 'kind': 'partition'},
          ],
          'openings': [
            {'id': 'ai-o-1', 'wall': 'ai-w-5', 'at': 0.5, 'w': 1, 'kind': 'door'},
          ],
          'spaces': [
            {'id': 'ai-sp-1', 'name': 'Northline Apparel', 'type': 'retail', 'shape': {'outer': [[2, 2], [10, 2], [10, 12], [2, 12]], 'holes': []}},
            {'id': 'ai-sp-2', 'name': '', 'type': 'retail', 'shape': {'outer': [[10, 2], [18, 2], [18, 12], [10, 12]], 'holes': []}},
          ],
          'outline': {'outer': [[2, 2], [18, 2], [18, 12], [2, 12]], 'holes': []},
          'uncertain': ['ai-sp-2'],
          'storeMatches': [
            {'spaceId': 'ai-sp-1', 'storeId': 1, 'storeName': 'Northline Apparel', 'exact': true},
          ],
          'crop': null,
        },
        'stats': {'walls': 5, 'doors': 1, 'spaces': 2, 'named': 1, 'uncertain': 1, 'wallMetres': 62},
        'notes': ['$longName: the right unit has no readable label.', '1 piece is marked uncertain (dashed amber). Check it before adding.'],
        'usedAi': true,
        'cost': {'model': 'gemini-2.5-pro-vision-preview-long-model-name', 'credits': credits, 'usd': 0.006},
      };

  // ---- Round 19: AI credits, Requests & reports, problem reports ----

  static Map<String, dynamic> creditRequestJson({int id = 1, String status = 'pending'}) => {
        'id': id,
        'userId': 3,
        'user': longPerson,
        'email': longEmail,
        'userActive': true,
        'branch': longName,
        'balance': 2.5,
        'amount': 5,
        'status': status,
        'decidedAmount': status == 'approved' ? 4 : null,
        'decidedBy': status == 'pending' ? null : longPerson,
        'declineReason': status == 'declined' ? 'Enough for this month.' : null,
        'createdAt': '2026-10-23T09:15:00',
        'decidedAt': status == 'pending' ? null : '2026-10-23T10:00:00',
      };

  static Map<String, dynamic> reportJson({int id = 1, String status = 'new', String type = 'broken', String? subject, String? pagePath = '/mall-admin/map-editor'}) => {
        'id': id,
        'reporterId': 3,
        'reporter': longPerson,
        'reporterEmail': longEmail,
        'reporterRole': 'mall_admin',
        'type': type,
        'subject': subject ?? 'The map draft does not save after adding a very long room name to the ground floor',
        'body': 'I added a room called "$longName" and pressed save; the editor showed an error and the change was gone.',
        'pagePath': pagePath,
        'status': status,
        'open': status == 'new' || status == 'in_progress',
        'waiting': status == 'new',
        'messageCount': status == 'new' ? 0 : 2,
        'createdAt': '2026-10-23T08:00:00',
        'updatedAt': '2026-10-23T09:30:00',
        'closedAt': null,
        'closedBy': status == 'resolved' || status == 'closed' ? longPerson : null,
      };

  Map<String, dynamic>? _credits(String path, String method) {
    if (path == '/requests/counts') return {'profile': 1, 'credits': 1, 'reports': 1, 'total': 3};
    if (path == '/ai/credits/mine') {
      return {
        'balance': aiMine.$1,
        'full': aiMine.$2,
        'cap': 20,
        'avgCost': creditsAvgCost,
        'request': creditRequestPending ? creditRequestJson() : null,
      };
    }
    if (path == '/ai/credits/overview') {
      final owner = role == 'supervisor';
      return {
        'days': 30,
        'cap': 20,
        'wallet': owner ? null : {'wallet': 82, 'given': 36, 'free': 46, 'used': 18, 'overGiven': 0, 'full': 100},
        'admins': [
          {'id': 3, 'name': longPerson, 'email': longEmail, 'branch': longName, 'balance': 12.5, 'full': 20, 'used': 7.25, 'readings': 14, 'lastReading': '2026-10-22T16:40:00'},
          {'id': 5, 'name': 'Jun Reyes', 'email': 'jun@liqo.local', 'branch': 'Robinsons Galleria', 'balance': 0.4, 'full': 5, 'used': 4.6, 'readings': 9, 'lastReading': '2026-10-23T08:10:00'},
          {'id': 6, 'name': 'Ana Cruz', 'email': 'ana@liqo.local', 'branch': null, 'balance': 0, 'full': null, 'used': 0, 'readings': 0, 'lastReading': null},
        ],
        'usage': {
          'total': 11.85,
          'series': [
            {'day': '2026-10-21', 'credits': 4.2, 'readings': 8},
            {'day': '2026-10-22', 'credits': 5.15, 'readings': 10},
            {'day': '2026-10-23', 'credits': 2.5, 'readings': 5},
          ],
        },
        'requests': owner ? null : {'waiting': 1, 'items': [creditRequestJson()]},
      };
    }
    if (path == '/ai/credits/history') {
      return paged([
        for (var i = 0; i < 3; i++)
          {
            'id': 10 - i,
            'userId': 3,
            'user': longPerson,
            'delta': i == 0 ? -0.5 : 5,
            'balanceAfter': 12.5 - i,
            'kind': i == 0 ? 'reading' : 'grant',
            'note': i == 1 ? 'For the new wing with a rather long note attached to it' : null,
            'conversionId': null,
            'requestId': null,
            'actor': longPerson,
            'createdAt': '2026-10-23T09:00:00',
          },
      ]);
    }
    if (path == '/ai/credits/requests' && method == 'GET') return paged([creditRequestJson(), creditRequestJson(id: 2, status: 'approved')]);
    if (path == '/ai/credits/requests' && method == 'POST') return {'request': creditRequestJson()};
    if (path == '/ai/credits/requests/mine') return {'request': creditRequestJson(status: 'cancelled')};
    final req = RegExp(r'^/ai/credits/requests/(\d+)(/approve|/decline)?$').firstMatch(path);
    if (req != null) {
      final id = int.parse(req.group(1)!);
      if (req.group(2) == '/approve') return {'request': creditRequestJson(id: id, status: 'approved')};
      if (req.group(2) == '/decline') return {'request': creditRequestJson(id: id, status: 'declined')};
      return {'request': creditRequestJson(id: id, status: id == 2 ? 'approved' : 'pending'), 'limits': {'free': 46, 'overGiven': 0, 'cap': 20, 'room': 17.5}};
    }
    if (RegExp(r'^/ai/credits/\d+/adjust$').hasMatch(path)) return {'balance': 17.5};
    return null;
  }

  Map<String, dynamic>? _reports(String path, String method) {
    if (path == '/reports/mine') return paged([reportJson(), reportJson(id: 2, status: 'resolved', type: 'question', subject: 'How do I add a level?')]);
    if (path == '/reports' && method == 'GET') return paged([reportJson(), reportJson(id: 2, status: 'in_progress', type: 'wrong_data')]);
    final one = RegExp(r'^/reports/(\d+)(/messages|/status)?$').firstMatch(path);
    if (one != null) {
      final id = int.parse(one.group(1)!);
      final status = one.group(2) == '/status' ? 'in_progress' : (id == 2 ? 'resolved' : 'new');
      return {
        'report': reportJson(id: id, status: status),
        'messages': [
          if (id == 2 || one.group(2) != null) {'id': 1, 'authorId': 1, 'author': longPerson, 'authorRole': 'superadmin', 'body': 'Thanks, looking into it now. Which floor was it?', 'createdAt': '2026-10-23T09:00:00'},
          if (one.group(2) == '/messages') {'id': 2, 'authorId': 3, 'author': longPerson, 'authorRole': 'mall_admin', 'body': 'The ground floor.', 'createdAt': '2026-10-23T09:20:00'},
        ],
      };
    }
    return null;
  }

  Map<String, dynamic> _answer(String path, String method) {
    requests.add('$method $path');
    if (path == '/ai/status' && role == 'mall_admin') {
      // Round 19: a mall admin sees only their own credits, never the wallet.
      return {
        'configured': aiConfigured,
        'model': aiConfigured ? aiModel : null,
        'quota': null,
        'quotaError': null,
        'gatewayBlocked': aiBlocked,
        'mine': {'balance': aiMine.$1, 'full': aiMine.$2},
      };
    }
    final credits = _credits(path, method);
    if (credits != null) return credits;
    final reports = _reports(path, method);
    if (reports != null) return reports;
    if (path == '/ai/status') {
      return {
        'configured': aiConfigured,
        'model': aiConfigured ? aiModel : null,
        'quota': !aiConfigured
            ? null
            : aiBlocked
                ? {'balance': 0, 'usedToday': 0, 'dailyCap': null, 'full': 40, 'blocked': true, 'reason': 'Out of AI credits. Contact your administrator to top up.'}
                : {'balance': aiWallet?.$1 ?? 123456.75, 'usedToday': 37.5, 'dailyCap': 50, 'full': aiWallet?.$2 ?? 150000, 'blocked': false, 'reason': null, 'given': 36, 'free': 46, 'overGiven': 0},
        'quotaError': null,
      };
    }
    if (path == '/ai/models') {
      return {
        'items': [
          {'id': 'gemini-2.5-pro-vision-preview-long-model-name', 'label': 'Google: Gemini 2.5 Pro Vision Preview (long label)', 'provider': 'gemini'},
          {'id': 'gpt-4o', 'label': 'GPT-4o', 'provider': 'openai'},
          {'id': 'gpt-5.1', 'label': 'GPT-5.1', 'provider': 'openai'},
        ],
        'current': aiModel,
      };
    }
    if (path == '/ai/model') return {'model': 'gpt-4o'};
    if (RegExp(r'^/maps/\d+/backdrops/\w+/unit$').hasMatch(path)) {
      final b = {...backdropJson('nounit.dxf'), 'units': 'mm', 'mpp': 0.005, 'needsUnit': false};
      uploadedBackdrops
        ..clear()
        ..add(b);
      return {'backdrop': b};
    }
    if (RegExp(r'^/maps/\d+/backdrops$').hasMatch(path)) return {'items': uploadedBackdrops};
    if (RegExp(r'^/maps/\d+/draft$').hasMatch(path)) return {'draftVersion': 2, 'publishProblems': <String>[], 'warnings': <Object>[], 'spaceCount': 2};
    if (RegExp(r'^/stores/\d+/spaces$').hasMatch(path)) return {'spaces': <String>[]};
    if (path == '/auth/me') return {'user': userJson(role: role)};
    if (path == '/auth/logout') return {'ok': true};
    if (path == '/analytics/overview') {
      return {
        'counts': {'malls': 3, 'branches': 7, 'stores': 120, 'accounts': 19, 'logins7d': 42, 'liveAnnouncements': 5, 'pendingAnnouncements': 4, 'mapPublications': 6},
        'recent': [
          {'id': 1, 'actorEmail': longEmail, 'action': 'mall_admin_assignments_updated_for_a_very_long_action_name', 'entityType': 'user', 'entityId': '1', 'createdAt': '2026-10-21T08:00:00'},
          {'id': 2, 'actorEmail': null, 'action': 'login_failed', 'entityType': null, 'entityId': null, 'createdAt': '2026-10-21T07:00:00'},
        ],
      };
    }
    if (path == '/analytics/report') return sampleReport(7);
    if (path == '/accounts') {
      return paged([
        userJson(id: 1, role: 'superadmin'),
        {...userJson(id: 2, role: 'supervisor'), 'mustChangePassword': true, 'access': {'malls': 0, 'branches': 0, 'stores': 0}},
        {...userJson(id: 3, role: 'mall_admin'), 'isActive': false, 'lastLoginAt': null, 'reportsTo': {'id': 2, 'name': longPerson}},
        {...userJson(id: 5, role: 'mall_admin')},
        {...userJson(id: 4, role: 'store_owner'), 'access': {'malls': 0, 'branches': 0, 'stores': 3}},
      ]);
    }
    if (RegExp(r'^/malls/\d+/people$').hasMatch(path)) return mallPeopleJson();
    if (RegExp(r'^/malls/\d+$').hasMatch(path)) return {'mall': mallPeopleJson()['mall'], 'canManage': role != 'supervisor'};
    if (RegExp(r'^/branches/\d+$').hasMatch(path)) {
      final b = Map<String, dynamic>.of((_answer('/branches', 'GET')['items'] as List).first as Map<String, dynamic>);
      if (inactiveBranch) b['isActive'] = false;
      return {'branch': b};
    }
    if (path == '/profile/request') return {'request': role == 'superadmin' ? null : profileRequestJson()};
    if (path == '/profile-requests') return paged([profileRequestJson(), {...profileRequestJson(id: 2), 'status': 'rejected', 'reason': 'Use your legal name, please, as it appears on your ID.'}]);
    if (RegExp(r'^/profile-requests/\d+$').hasMatch(path)) return {'request': profileRequestJson()};
    if (path == '/accounts/4') {
      return {'user': {...userJson(id: 4, role: 'store_owner'), 'access': null}, 'assignments': null};
    }
    if (path == '/accounts/9') {
      return {'user': {...userJson(id: 9, role: 'superadmin'), 'access': null}, 'assignments': null};
    }
    if (RegExp(r'^/accounts/\d+$').hasMatch(path)) {
      return {
        'user': {...userJson(id: 3, role: 'mall_admin'), 'reportsTo': {'id': 2, 'name': longPerson}},
        'assignments': {
          'branches': [
            {'id': 1, 'name': longName, 'mallId': 1, 'mallName': 'SM Prime Holdings Incorporated'},
          ],
        },
      };
    }
    if (RegExp(r'^/stores/\d+$').hasMatch(path)) {
      return {
        'store': (_answer('/stores', 'GET')['items'] as List).first,
        'spaceKeys': ['sp-a01', 'sp-a02', 'sp-a03'],
        'spaces': ['sp-a01'],
        'owners': [
          {'id': 4, 'email': longEmail, 'fullName': longPerson, 'isActive': true},
        ],
      };
    }
    if (RegExp(r'^/owners/\d+$').hasMatch(path)) return {'user': (_answer('/owners', 'GET')['items'] as List).first};
    if (RegExp(r'^/options/\d+$').hasMatch(path)) return {'option': (_answer('/options', 'GET')['items'] as List).first};
    if (RegExp(r'^/announcements/\d+$').hasMatch(path)) {
      final a = Map<String, dynamic>.of((_answer('/announcements', 'GET')['items'] as List).first as Map<String, dynamic>);
      if (sharedAnnouncement) {
        a['sharedBeyondScope'] = true;
        a['canChange'] = false;
        a['canDetach'] = true;
      }
      return {'announcement': a};
    }
    if (path == '/profile/access') {
      return switch (role) {
        'supervisor' => {'role': role, 'malls': [{'id': 1, 'name': 'SM Prime Holdings'}], 'branches': [{'id': 2, 'name': longName, 'mallName': 'Robinsons'}]},
        'mall_admin' => {'role': role, 'branches': [{'id': 1, 'name': longName, 'mallId': 1, 'mallName': 'SM Prime'}], 'reportsTo': {'id': 2, 'name': longPerson}},
        'store_owner' => {'role': role, 'stores': [{'id': 1, 'name': 'Northline Apparel', 'branchName': longName}]},
        _ => {'role': role},
      };
    }
    if (path == '/malls') {
      return paged([
        {'id': 1, 'name': 'SM Prime Holdings Incorporated Shopping Centers Division', 'logoUrl': 'https://logos.example-mall-company.com/sm-prime.png', 'isActive': true, 'branchCount': 12},
        {'id': 2, 'name': 'Robinsons', 'logoUrl': null, 'isActive': false, 'branchCount': 0},
      ]);
    }
    if (path == '/branches') {
      return paged([
        {
          'id': 1,
          'mallId': 1,
          'mallName': 'SM Prime Holdings Incorporated',
          'name': longName,
          'address': 'Seaside Boulevard corner J.W. Diokno Boulevard, Mall of Asia Complex, Bay City, Pasay, 1300 Metro Manila, Philippines',
          'openingHours': 'Monday to Sunday 10:00 AM to 10:00 PM, extended to midnight on holidays',
          'isActive': true,
        },
        {'id': 2, 'mallId': 2, 'mallName': 'Robinsons', 'name': 'Galleria', 'isActive': false},
      ]);
    }
    if (path == '/audit') {
      return paged([
        {'id': 1, 'actorEmail': longEmail, 'action': 'mall_admin_assignments_updated', 'entityType': 'user', 'entityId': '12345', 'details': {'branchIds': [1, 2, 3], 'note': longName}, 'ip': '255.255.255.255', 'createdAt': '2026-10-21T08:00:00'},
        {'id': 2, 'actorEmail': null, 'action': 'login_failed', 'entityType': null, 'entityId': null, 'details': null, 'ip': null, 'createdAt': '2026-10-21T07:00:00'},
      ]);
    }
    if (path == '/audit/actions') return {'actions': ['login_success', 'login_failed', 'mall_admin_assignments_updated']};
    if (path == '/settings') {
      return {
        'settings': {'min_password_length': 8, 'ai_file_size_mb': 20, 'default_announcement_days': 7, 'session_timeout_hours': 8, 'max_login_attempts': 5, 'ai_model': 'gpt-4o', 'ai_start_credits': 3, 'ai_credit_cap': 20},
        'rules': {
          'min_password_length': {'min': 6, 'max': 64, 'label': 'Minimum password length'},
          'ai_file_size_mb': {'min': 1, 'max': 50, 'label': 'AI file size limit (MB)'},
          'default_announcement_days': {'min': 1, 'max': 365, 'label': 'Default announcement duration (days)'},
          'session_timeout_hours': {'min': 1, 'max': 72, 'label': 'Session timeout (hours)'},
          'max_login_attempts': {'min': 3, 'max': 20, 'label': 'Max failed sign-ins before lockout'},
          'ai_start_credits': {'min': 0, 'max': 1000, 'label': 'Starting AI credits for a new mall admin'},
          'ai_credit_cap': {'min': 1, 'max': 10000, 'label': 'Most AI credits per mall admin'},
        },
      };
    }
    if (path == '/announcements/defaults') return {'startsOn': '2026-10-21', 'endsOn': '2026-10-28'};
    if (path == '/announcements') {
      return paged([
        {
          'id': 1,
          'title': 'Grand Anniversary Mega Sale with Extended Mall Hours and Live Performances',
          'body': 'Long body text ' * 20,
          'startsOn': '2026-10-01',
          'endsOn': '2026-10-31',
          'status': 'pending',
          'liveState': 'live',
          'storeId': 1,
          'storeName': 'Northline Apparel Flagship Boutique',
          'createdBy': 4,
          'createdByName': longPerson,
          'createdRole': 'store_owner',
          'branches': [
            {'id': 1, 'name': longName, 'mallName': 'SM Prime'},
          ],
          'createdAt': '2026-10-15T08:00:00',
        },
        {
          'id': 2,
          'title': 'Short',
          'body': 'x',
          'startsOn': '2026-11-01',
          'endsOn': '2026-11-02',
          'status': 'rejected',
          'liveState': 'upcoming',
          'createdBy': 2,
          'createdByName': 'Sup',
          'createdRole': 'supervisor',
          'reviewedByName': 'Reviewer With A Long Name',
          'rejectReason': 'Reason text that goes on and on and on for the layout test',
          'branches': [],
          'createdAt': '2026-10-15T08:00:00',
        },
      ]);
    }
    if (path == '/stores') {
      return paged([
        {'id': 1, 'branchId': 1, 'branchName': longName, 'mallName': 'SM Prime', 'name': 'Northline Apparel Flagship Boutique and Outlet', 'categoryId': 1, 'categoryName': 'Apparel and Fashion Accessories', 'openingHours': 'Mon–Sun 10:00 AM – 10:00 PM', 'contactPhone': '+63 2 8888 8888', 'contactEmail': longEmail, 'isActive': true, 'spaceCount': 3, 'ownerCount': 2},
        {'id': 2, 'branchId': 1, 'branchName': 'B', 'mallName': 'M', 'name': 'S', 'isActive': false, 'spaceCount': 0, 'ownerCount': 0},
      ]);
    }
    if (path == '/owners') {
      return paged([
        {
          'id': 4,
          'email': longEmail,
          'fullName': longPerson,
          'isActive': true,
          'mustChangePassword': true,
          'lastLoginAt': '2026-10-21T08:00:00',
          'stores': [
            {'id': 1, 'name': 'Northline Apparel Flagship Boutique and Outlet', 'branchId': 1, 'branchName': longName, 'isActive': true},
            {'id': 2, 'name': 'Second Store', 'branchId': 1, 'branchName': longName, 'isActive': false},
          ],
        },
      ]);
    }
    if (path == '/options') {
      return paged([
        {'id': 1, 'branchId': 1, 'kind': 'store_category', 'name': 'Apparel and Fashion Accessories for the Whole Family', 'sortOrder': 1, 'isActive': true, 'inUse': 12},
        {'id': 2, 'branchId': 1, 'kind': 'floor_label', 'name': 'G', 'sortOrder': 2, 'isActive': false, 'inUse': 0},
      ]);
    }
    if (path == '/maps/catalog') return _catalog;
    if (RegExp(r'^/maps/\d+$').hasMatch(path)) return _mapBundle();
    if (path == '/maps') {
      return {
        'items': [
          if (mapLocked)
            {'branchId': 1, 'branchName': longName, 'mallName': 'SM Prime', 'hasMap': true, 'draftVersion': 4, 'publishedVersion': 3, 'spaceCount': 48, 'lockedBy': {'userId': 3, 'userName': longPerson}},
        ],
      };
    }
    if (path.startsWith('/lookups/')) {
      return paged([
        {'id': 1, 'label': '$longName · $longName', 'isActive': true},
        {'id': 2, 'label': 'Short', 'isActive': true},
      ]);
    }
    return paged([]);
  }

  /// The create wizards' live checks. Emails with "taken", "inactive" or
  /// "pending" in them hit those cases; in the store-owner wizard an email with
  /// "owner" belongs to an active store owner and one with "sleepy" to an
  /// inactive one. Names with "Santos" match two accounts. Account details
  /// come back only for a superadmin, like the server.
  Map<String, dynamic> _check(Map<String, String> q) {
    final out = <String, dynamic>{};
    final isSuper = role == 'superadmin';
    final email = q['email'];
    if (email != null) {
      final match = {'id': 3, 'fullName': longPerson, 'role': 'mall_admin', 'isActive': true};
      final storeOwner = q['purpose'] == 'store_owner';
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        out['email'] = {'state': 'invalid'};
      } else if (storeOwner && email.contains('sleepy')) {
        out['email'] = {'state': 'inactive', 'account': {'id': 4, 'fullName': longPerson, 'role': 'store_owner', 'isActive': false}, 'canOpen': true};
      } else if (storeOwner && email.contains('owner')) {
        out['email'] = {'state': 'store_owner', 'account': {'id': 4, 'fullName': longPerson, 'role': 'store_owner', 'isActive': true}, 'canOpen': true};
      } else if (email.contains('taken')) {
        out['email'] = isSuper ? {'state': 'taken', 'account': match, 'canOpen': true} : {'state': 'taken'};
      } else if (email.contains('inactive')) {
        out['email'] = isSuper ? {'state': 'inactive', 'account': {...match, 'isActive': false}, 'canOpen': true} : {'state': 'inactive'};
      } else if (email.contains('pending')) {
        out['email'] = {'state': 'pending_request'};
      } else {
        out['email'] = {'state': 'free'};
      }
    }
    final name = q['fullName'];
    if (name != null) {
      final hit = name.toLowerCase().contains('santos');
      out['name'] = {
        'count': hit ? 2 : 0,
        if (isSuper)
          'matches': hit
              ? [
                  {'id': 3, 'fullName': longPerson, 'role': 'mall_admin', 'isActive': true},
                  {'id': 5, 'fullName': 'Maria Santos', 'role': 'supervisor', 'isActive': false},
                ]
              : [],
      };
    }
    if (q['branchId'] != null && role != 'mall_admin') {
      out['branchAdmins'] = [
        {'id': 3, 'fullName': longPerson, 'isActive': true},
      ];
    }
    return out;
  }

  /// POST /accounts and POST /owners: what the create wizards save.
  Map<String, dynamic>? _created(String path, String method, Object? data) {
    if (method != 'POST') return null;
    if (RegExp(r'^/maps/\d+$').hasMatch(path)) {
      mapCreated = true;
      return {'map': {'id': 1}};
    }
    if (RegExp(r'^/maps/\d+/lock$').hasMatch(path)) {
      return {'lock': {'userId': 1, 'userName': longPerson, 'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(), 'mine': true}};
    }
    if (RegExp(r'^/maps/\d+/backdrops$').hasMatch(path)) {
      final name = data is FormData && data.files.isNotEmpty ? data.files.first.value.filename ?? 'plan.png' : 'plan.png';
      final b = backdropJson(name);
      uploadedBackdrops
        ..clear()
        ..add(b);
      return {'backdrop': b};
    }
    if (RegExp(r'^/maps/\d+/backdrops/\w+/convert$').hasMatch(path)) {
      final d = data is Map ? data : const {};
      return {...aiProposal(levelId: d['levelId'] as String? ?? 'lv-1'), if (aiScaleFound != null) 'scaleFound': aiScaleFound};
    }
    final d = data is Map ? data : const {};
    if (path == '/accounts') {
      return {
        'user': {...userJson(id: 77, role: d['role'] as String? ?? 'mall_admin'), 'email': d['email'] ?? longEmail, 'fullName': d['fullName'] ?? longPerson},
        'tempPassword': 'Tmp-7Kq2-Wx9p',
        if ((d['role'] as String? ?? 'mall_admin') == 'mall_admin') ...{'startCredits': 3, 'startNote': null},
      };
    }
    if (path == '/reports') {
      return {'report': reportJson(id: 9, type: d['type'] as String? ?? 'broken', subject: d['subject'] as String? ?? longName, pagePath: d['pagePath'] as String?)};
    }
    if (path == '/owners') {
      final existing = (d['email'] as String? ?? '').contains('owner');
      final owner = (_answer('/owners', 'GET')['items'] as List).first as Map<String, dynamic>;
      return {'user': owner, 'tempPassword': existing ? null : 'Tmp-3Hs8-Lm4c'};
    }
    return null;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    var path = options.uri.path;
    if (hang || (hangWhen != null && hangWhen!.hasMatch(path))) await Completer<void>().future;
    if (path.startsWith('/api')) path = path.substring(4);
    if (RegExp(r'^/maps/\d+/published$').hasMatch(path) && !mapCreated) {
      return ResponseBody.fromString(jsonEncode({'error': 'No published map for this branch yet.'}), 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    final answer = path == '/accounts/check'
        ? _check(options.uri.queryParameters)
        : (_created(path, options.method, options.data) ?? _answer(path, options.method));
    if (path == '/accounts/check' || options.method == 'POST') requests.add('${options.method} ${options.uri}');
    if (options.method != 'GET') writes.add((options.method, path, options.data));
    final body = jsonEncode(answer);
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
