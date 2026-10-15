# Backgrounds

The web app and Shiori Search (the hosted page and Safari's extension page) can draw a background behind the page:
an animated city at night, the rain over it, or a picture or video of your own. The native apps don't have them yet.

Pick one in Settings: the web app's **Appearance** page, or the search page's sheet under Appearance.

- **Background**: Off (the default), or a scene. Japan: Tokyo, Tokyo Alley, Osaka. Asia: Seoul, Hong Kong, Shanghai,
  Taipei, Singapore, Bangkok. Americas: San Francisco, Los Angeles, Chicago, Las Vegas. Films and Games: Los Angeles,
  2019, Neo-Tokyo, Walled City (with a Cat). Or **Your Picture or Video**.
- **Rain**: rain over the background, splashing on a scene's street.
- **Your Picture or Video**: Choose… picks a file (a picture is scaled to 2,400 pixels; a GIF or a video, up to
  100 MB, plays silently on a loop). Remove takes it away.

As everywhere in Settings, a change previews at once and only Save keeps it; Cancel puts back what was there.

While a background shows, two buttons sit in the lower-right corner: **Rain**, and the eye, **Watch**, which hides the
page so you see the background alone. A tap anywhere or Escape brings the page back.

## What stays where

Backgrounds belong to the browser you set them in: `localStorage` (`shioriBackground`) holds the choice, and IndexedDB
(`shiori-background`) holds your picture or video. Nothing is uploaded, nothing follows you to another device, and
Safari's page doesn't pass them to the Shiori app.

The scenes are drawn on the device by `patches/shiori/bg.js`, which comes from annai (another Machiya app, under the
same license): no network, no libraries. Its signs show Shiori's own words (your pills' names; Shiori as 栞 or 시오리).
The hosted pages' Content Security Policy allows `media-src 'self' blob:` for your video; a picture is shown as a
`data:` image, which the policy already allows.

## Performance

Off draws nothing: no canvas, no timers, and `bg.js` isn't loaded. A scene is drawn once per window width; each frame
only flickers its signs, blinks its beacons and moves its few extras, at most 30 times a second, at no more than 1.5
device pixels per point, and not at all while the page is hidden. With Reduce Motion on, a scene and the rain are one
still frame and a video shows its first frame.

## Reading over it

Text keeps its 4.5:1 contrast over any background. In a dark theme the page's panels are glass: they dim what's
behind them before blurring it under half the panel's own colour, so a panel can only get darker, never brighter
than its theme. About a twelfth of the scene shows through; the rest shows around the panels. In a light theme, with
Reduce Transparency, or where the browser can't blur, the panels stay solid. `scripts/theme-contrast.test.mjs` holds
this against the brightest each scene gets under the blur, and against a white picture of your own.

While the background moves (a scene, the rain or a video), the panels don't blur: the browser would blur the moving
layers again for every frame, which took more than a whole core in Firefox on Linux. They dim with black instead,
letting the same twelfth through, sharp; at that brightness it looks the same. A picture of your own keeps the blur.
