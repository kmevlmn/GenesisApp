import '../api_client.dart';
import 'app_api.dart';
import 'common_api.dart';
import 'discuss_api.dart';
import 'dm_api.dart';
import 'feedback_api.dart';
import 'follow_api.dart';
import 'gem_api.dart';
import 'home_api.dart';
import 'messages_api.dart';
import 'membership_api.dart';
import 'origin_api.dart';
import 'report_api.dart';
import 'search_api.dart';
import 'upload_api.dart';
import 'user_api.dart';
import 'world_api.dart';

class GenesisV1Api {
  GenesisV1Api(
    ApiClient client, {
    CurrentUserInfoSessionProvider? currentUserInfoSessionProvider,
  }) : app = AppV1Api(client),
       user = UserV1Api(
         client,
         currentUserInfoSessionProvider: currentUserInfoSessionProvider,
       ),
       origin = OriginV1Api(client),
       world = WorldV1Api(client),
       messages = MessagesV1Api(client),
       dm = DmV1Api(client),
       feedback = FeedbackV1Api(client),
       follow = FollowV1Api(client),
       discuss = DiscussV1Api(client),
       report = ReportV1Api(client),
       search = SearchV1Api(client),
       home = HomeV1Api(client),
       gem = GemV1Api(client),
       membership = MembershipV1Api(client),
       upload = UploadV1Api(client),
       common = CommonV1Api(client);

  final AppV1Api app;
  final UserV1Api user;
  final OriginV1Api origin;
  final WorldV1Api world;
  final MessagesV1Api messages;
  final DmV1Api dm;
  final FeedbackV1Api feedback;
  final FollowV1Api follow;
  final DiscussV1Api discuss;
  final ReportV1Api report;
  final SearchV1Api search;
  final HomeV1Api home;
  final GemV1Api gem;
  final MembershipV1Api membership;
  final UploadV1Api upload;
  final CommonV1Api common;
}
