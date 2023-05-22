const WORK_CHROME = {
  name: "Google Chrome",
  profile: "Default"
};

const HOME_CHROME = {
  name: "Google Chrome",
  profile: "Profile 1",
};

const NEW_CHROME_WINDOW = (options) => {
  return {
    ...WORK_CHROME,
    args: ['--new-window', options.urlString],
  }
};

module.exports = {
  defaultBrowser: "Google Chrome",
  options: {
    logRequests: true,
  },
  handlers: [
    {
      match: /^https?:\/\/meet\.google\.com\/.*$/,
      browser: NEW_CHROME_WINDOW
    },
    {
      match: /fernet.io/,
      browser: WORK_CHROME,
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
      match: /mychart.seattlechildrens.org/,
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
    }
  ]
}
