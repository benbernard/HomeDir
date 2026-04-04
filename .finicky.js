const WORK_CHROME = {
  name: "Google Chrome",
  profile: "Default"
};

const HOME_CHROME = {
  name: "Google Chrome",
  profile: "Profile 1",
};

// const LINEAR_APP = () => {
//   return {
//     name: ""
//   }
// }
//
const LINEAR_APP = {
  name: "Linear",
}

const NEW_CHROME_WINDOW = (options) => {
  return {
    ...WORK_CHROME,
    args: ['--new-window', options.urlString],
  }
};

const MEET_IN_ONE = (options) => {
  return {
    name: '/Applications/MeetInOne.app',
  }
};

const MEETY = {
  name: "/Applications/Meety.app",
};

export default {
  defaultBrowser: "Google Chrome",
  options: {
    logRequests: true,
  },
  rewrite: [
    {
      match: /^https?:\/\/instacart(\.enterprise)?\.slack\.com\/archives\//,
      url: (url) => {
        const TEAM_ID = "E01BJF2PY8N";
        const parts = url.pathname.split("/").filter(Boolean);
        // parts = ["archives", "C08K9HQFGM6", "p1774979830031829"]
        const channelId = parts[1];
        const rawMsg = parts[2];
        if (!channelId) return url.href;
        let deepLink = `slack://channel?team=${TEAM_ID}&id=${channelId}`;
        if (rawMsg && rawMsg.startsWith("p")) {
          const ts = rawMsg.slice(1);
          const timestamp = ts.slice(0, 10) + "." + ts.slice(10);
          deepLink += `&message=${timestamp}`;
        }
        const threadTs = url.searchParams.get("thread_ts");
        if (threadTs) {
          deepLink += `&thread_ts=${threadTs}`;
        }
        return deepLink;
      },
    },
  ],
  handlers: [
    {
      match: (url) => url.protocol === "slack:",
      browser: "Slack",
    },
    {
      match: /zoom.us/,
      browser: WORK_CHROME,
    },
    {
      match: /call.benjaminbernard.com/,
      browser: WORK_CHROME,
    },
    {
      match: /app\.krisp\.ai/,
      browser: WORK_CHROME,
    },
    {
      match: /^https?:\/\/meet\.google\.com\/.*$/,
      browser: MEETY,
    },
    {
      match: /fernet.io/,
      browser: WORK_CHROME,
    },
    // This must come before the instacart to workchrome handler
    {
      match: /^(https?:\/\/)linear.app\//,
      browser: LINEAR_APP,
    },
    {
      match: /instacart/,
      browser: WORK_CHROME,
    },
    {
      match: /^https?:\/\/github.com/,
      browser: WORK_CHROME,
    },
    {
      match: /http:\/\/home\.ben/,
      browser: HOME_CHROME,
      url: (url) => {
        return "https://google.com"
      },
    },
    {
      match: /crabanddog\.com/,
      browser: HOME_CHROME,
    },
    {
      match: /youtube.com/,
      browser: HOME_CHROME,
    },
    {
      match: /aws.amazon.com/,
      browser: WORK_CHROME,
    },
    {
      match: /amazon.com/,
      browser: HOME_CHROME,
    },
    {
      match: /mychart.seattlechildrens.org/,
      browser: HOME_CHROME,
    },
    {
      match: /linkedin.com/,
      browser: HOME_CHROME,
    },
    {
      match: /^https?:\/\/airtable.com/,
      browser: HOME_CHROME,
    },
    {
      match: /^https?:\/\/golinks.io/,
      browser: WORK_CHROME,
    },
    {
      match: /^(https?:\/\/)?go\//,
      browser: WORK_CHROME,
    },
    {
      match: /tailscale.com/,
      browser: WORK_CHROME
    }

  ],
}
