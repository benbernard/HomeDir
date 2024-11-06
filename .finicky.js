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

const MEETING_CHROME = (options) => {
  return {
    name: "/Users/benbernard/bin/OpenMeetAS.app",
    appType: 'appPath'
  }
}

module.exports = {
  defaultBrowser: "Google Chrome",
  options: {
    logRequests: true,
  },
  // rewrite: [{
  //   match: /^https?:\/\/meet\.google\.com\/.*$/,
  //   url: (options) => {
  //     return 'meetinone://url=' + options.urlString
  //   },
  // }],
  handlers: [
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
      browser: MEETING_CHROME,
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
