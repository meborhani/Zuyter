# Setup (about 20 minutes, once)

1. The Instagram account must be **Professional** (Business or Creator).
2. Go to https://developers.facebook.com, create an app (type **Business**), add the product
   **Instagram** and choose **API setup with Instagram login**.
3. Under that product, add the Instagram account as a tester / connect it, and generate an
   **access token** with these permissions: `instagram_business_basic`,
   `instagram_business_manage_insights`, `instagram_business_manage_comments`,
   `instagram_business_content_publish`.
4. Exchange it for a long-lived token (about 60 days, refreshable) as shown in Meta's docs.
5. Add it as an environment network secret: Bearer, allowed website `graph.instagram.com`, header `Authorization` with prefix `Bearer` and the token as value. (Or export `IG_ACCESS_TOKEN` locally; never commit it.)
6. Test: `python3 .claude/skills/ig-api/ig_api.py me`

While the app is in development mode only accounts you add as testers work, which is
fine for your own page. Publishing to other people's accounts needs Meta app review.
