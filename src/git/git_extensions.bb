#!/usr/bin/env bb

;;; ============================================================
;;; Git Extensions Framework
;;; ============================================================
;;;
;;; A multi-command git extension framework.
;;; Create symlinks like `git-deploy` pointing to this script.
;;; The script detects the command from the symlink name.
;;;
;;; Supported extensions:
;;;   - vendor: Clone repositories to ~/git/vendor/{org}/{repo}
;;;   - deploy: Clone repositories using deploy key authentication
;;;   - deploy-key: Manage deploy keys (list, show, remove)
;;;   - remote-proto: Convert remote URL protocol (https, git, ssh)
;;;
;;; ============================================================

(ns git-extensions
  (:require [babashka.fs :as fs]
            [babashka.process :as proc]
            [clojure.string :as str]
            [clojure.java.io :as io]))

(def original-args *command-line-args*)
(def home (System/getProperty "user.home"))

;;; ============================================================
;;; Common Utilities
;;; ============================================================

(defn stderr [& args]
  (binding [*out* *err*]
    (apply println args)))

(defn error [& args]
  (apply stderr "Error:" args))

(defn fault [& [msg]]
  (when msg (error msg))
  (stderr "Exiting.")
  (System/exit 1))

(defn check-deps [& deps]
  (let [missing (remove #(fs/which %) deps)]
    (when (seq missing)
      (fault (str "Missing dependencies: " (str/join " " missing))))))

(defn ask-yes-no
  "Prompt for yes/no confirmation. Returns true for yes."
  ([prompt] (ask-yes-no prompt nil))
  ([prompt default]
   (loop []
     (let [suffix (case default "y" " [Y/n] " "n" " [y/N] " " [y/n] ")]
       (print (str prompt suffix))
       (flush)
       (let [reply (str/lower-case (str/trim (or (read-line) "")))
             reply (if (str/blank? reply) (or default "") reply)]
         (case reply
           ("y" "yes") true
           ("n" "no") false
           (do (println "Please answer yes or no.") (recur))))))))

(defn ask-input
  "Prompt for text input with optional default."
  ([prompt] (ask-input prompt nil))
  ([prompt default]
   (if default
     (do (print (str prompt " [" default "] ")) (flush)
         (let [reply (str/trim (or (read-line) ""))]
           (if (str/blank? reply) default reply)))
     (do (print (str prompt " ")) (flush)
         (str/trim (or (read-line) ""))))))

;;; Git helpers — all take an explicit directory

(defn git-out
  "Run git in dir, return trimmed stdout or nil on failure."
  [dir & args]
  (let [r (apply proc/shell {:dir dir :out :string :err :string :continue true} "git" args)]
    (when (zero? (:exit r))
      (str/trim (:out r)))))

(defn git-ok?
  "Run git in dir, return true if exit 0."
  [dir & args]
  (zero? (:exit (apply proc/shell {:dir dir :out :string :err :string :continue true} "git" args))))

(defn git!
  "Run git in dir with output to terminal, exit on failure."
  [dir & args]
  (let [r (apply proc/shell {:dir dir :continue true} "git" args)]
    (when-not (zero? (:exit r))
      (fault (str "git " (str/join " " args) " failed")))
    r))

;;; ============================================================
;;; URL Parsing (shared)
;;; ============================================================

(defn parse-remote-url
  "Parse a git remote URL. Returns {:host :path} or nil."
  [url]
  (let [url (str/replace url #"\.git$" "")]
    (or (when-let [[_ host path] (re-matches #"git@([^:]+):(.+)" url)]
          {:host host :path path})
        (when-let [[_ _ host path] (re-matches #"ssh://([^@]+@)?([^/]+)/(.+)" url)]
          {:host host :path path})
        (when-let [[_ host path] (re-matches #"https?://([^/]+)/(.+)" url)]
          {:host host :path path}))))

;;; ============================================================
;;; Deploy Extension
;;; ============================================================

(defn deploy-parse-repo-spec
  "Parse 'url#branch' → {:url :branch}."
  [spec]
  (if-let [[_ url branch] (re-matches #"(.+)#([^#]+)" spec)]
    {:url url :branch branch}
    {:url spec :branch nil}))

(defn deploy-default-destination
  "Derive ~/git/vendor/{org}/{repo} from URL."
  [url]
  (if-let [{:keys [path]} (parse-remote-url url)]
    (let [path (str/replace path #"^/" "")
          parts (str/split path #"/")
          org (str/lower-case (first parts))
          repo (last parts)]
      (str home "/git/vendor/" org "/" repo))
    ;; Fallback: just repo name
    (-> url (str/replace #"\.git$" "") (str/split #"/") last)))

(defn deploy-normalize-url
  "Normalize URL to SSH format (git@host:path.git)."
  [url]
  (let [url (str/replace url #"\.git$" "")]
    (cond
      (re-matches #"https?://([^/]+)/(.+)" url)
      (let [[_ host path] (re-matches #"https?://([^/]+)/(.+)" url)]
        (str "git@" host ":" path ".git"))

      (str/starts-with? url "git@")
      (str url ".git")

      (str/starts-with? url "ssh://")
      (let [rest (-> url (str/replace #"^ssh://" "") (str/replace #"^[^@]+@" ""))]
        (if-let [[_ host _ _ path] (re-matches #"([^:/]+)(:([0-9]+))?/(.+)" rest)]
          (str "git@" host ":" path ".git")
          (str url ".git")))

      :else (str url ".git"))))

(defn deploy-alias-url?
  "Check if URL uses a deploy key alias (git@deploy-...)."
  [url]
  (boolean (re-find #"^git@deploy-" url)))

(defn deploy-extract-alias
  "Extract alias from git@alias:path URL."
  [url]
  (second (re-matches #"git@([^:]+):.*" url)))

(defn deploy-convert-remote-url
  "Convert a remote URL to use the deploy key alias."
  [url alias]
  (if-let [{:keys [path]} (parse-remote-url url)]
    (str "git@" alias ":" path ".git")
    (fault (str "Cannot parse remote URL: " url))))

;;; --- SSH Config Management ---

(def ssh-config-file (str home "/.ssh/config"))

(defn ssh-keys-dir []
  (let [dir (str home "/.ssh/deploy-keys")]
    (fs/create-dirs dir)
    (fs/set-posix-file-permissions dir "rwx------")
    dir))

(defn deploy-generate-alias [host path]
  (-> (str "deploy--" host "--" path)
      (str/replace #"/" "-")
      (str/replace #"-{2,}" "-")))

(defn deploy-key-file-path [alias]
  (str (ssh-keys-dir) "/" alias))

(defn deploy-host-alias-exists? [alias]
  (and (fs/exists? ssh-config-file)
       (some #(= (str/trim %) (str "Host " alias))
             (str/split-lines (slurp ssh-config-file)))))

(defn- remove-host-block
  "Remove a Host block from SSH config content."
  [content alias]
  (let [lines (str/split-lines content)]
    (->> (loop [[line & more] lines skip false result []]
           (if (nil? line)
             result
             (if (re-matches #"Host .+" line)
               (if (= (str/trim line) (str "Host " alias))
                 (recur more true result)
                 (recur more false (conj result line)))
               (if skip
                 (recur more skip result)
                 (recur more false (conj result line))))))
         (str/join "\n"))))

(defn deploy-add-host-alias [alias real-host key-file & [port]]
  (fs/create-dirs (fs/parent ssh-config-file))
  (let [existing (if (fs/exists? ssh-config-file) (slurp ssh-config-file) "")
        separator (cond
                    (str/blank? existing) ""
                    (not (str/ends-with? existing "\n")) "\n\n"
                    :else "\n")
        entry (str separator
                   "Host " alias "\n"
                   "    HostName " real-host "\n"
                   (when port (str "    Port " port "\n"))
                   "    User git\n"
                   "    IdentityFile " key-file "\n"
                   "    IdentitiesOnly yes\n")]
    (spit ssh-config-file entry :append true)
    (fs/set-posix-file-permissions ssh-config-file "rw-------")
    (stderr (str "## Added SSH host alias '" alias "'"))))

(defn deploy-remove-host-alias [alias]
  (when (fs/exists? ssh-config-file)
    (spit ssh-config-file (remove-host-block (slurp ssh-config-file) alias))
    (fs/set-posix-file-permissions ssh-config-file "rw-------")))

(defn deploy-update-host-alias [alias real-host key-file & [port]]
  (deploy-remove-host-alias alias)
  (deploy-add-host-alias alias real-host key-file port))

(defn deploy-generate-key [key-file comment]
  (proc/shell {:out :string :err :string}
              "ssh-keygen" "-t" "ed25519" "-f" key-file "-N" "" "-C" comment)
  (fs/set-posix-file-permissions key-file "rw-------")
  (fs/set-posix-file-permissions (str key-file ".pub") "rw-r--r--")
  (stderr (str "## Generated new deploy key: " key-file)))

;;; --- Deploy Key Setup ---

(defn deploy-setup-key
  "Setup deploy key for a remote in a given repo dir.
   Returns {:alias :key-file :created?}."
  [dir remote-name repo-port]
  (let [remote-url (or (git-out dir "remote" "get-url" remote-name)
                       (fault (str "Remote '" remote-name "' not found")))]
    (if (deploy-alias-url? remote-url)
      ;; Already configured
      (let [alias (deploy-extract-alias remote-url)]
        (stderr (str "## Already configured with deploy key: " alias))
        {:alias alias :key-file (deploy-key-file-path alias) :created? false})
      ;; Parse and setup
      (let [{:keys [host path]} (or (parse-remote-url remote-url)
                                    (fault (str "Cannot parse remote URL: " remote-url)))
            _ (stderr (str "## Host: " host))
            _ (stderr (str "## Path: " path))
            alias (deploy-generate-alias host path)
            key-file (deploy-key-file-path alias)
            _ (stderr (str "## SSH alias: " alias))
            _ (stderr (str "## Key file: " key-file))
            created? (if (fs/exists? key-file)
                       (do (stderr "## Deploy key already exists") false)
                       (let [hostname (or (System/getenv "HOSTNAME") "localhost")]
                         (deploy-generate-key key-file
                           (str "deploy-key@" hostname " " host ":" path))
                         true))]
        (if (deploy-host-alias-exists? alias)
          (stderr "## SSH host alias already configured")
          (deploy-add-host-alias alias host key-file repo-port))
        ;; Update remote URL
        (let [new-url (deploy-convert-remote-url remote-url alias)]
          (when (not= remote-url new-url)
            (git! dir "remote" "set-url" remote-name new-url)
            (stderr "## Updated remote URL to use deploy key")))
        {:alias alias :key-file key-file :created? created?}))))

;;; --- Deploy Repository Setup ---

(defn deploy-init-repo [dest url remote-name]
  (if (fs/directory? dest)
    (if (fs/directory? (str dest "/.git"))
      (do (stderr (str "## Directory already contains a git repository: " dest))
          (stderr "## Updating configuration..."))
      (fault (str "Directory exists but is not a git repository: " dest)))
    (do (fs/create-dirs dest)
        (stderr (str "## Created directory: " dest))))
  (when-not (fs/directory? (str dest "/.git"))
    (git! dest "init" "--quiet")
    (stderr "## Initialized empty git repository")
    (git! dest "symbolic-ref" "HEAD" "refs/heads/__deploy_pending__"))
  (if (git-out dest "remote" "get-url" remote-name)
    (do (git! dest "remote" "set-url" remote-name url)
        (stderr (str "## Updated remote '" remote-name "': " url)))
    (do (git! dest "remote" "add" remote-name url)
        (stderr (str "## Added remote '" remote-name "': " url))))
  (git! dest "config" "checkout.defaultRemote" remote-name))

(defn deploy-test-key [dir remote-name & [timeout-secs]]
  (let [t (str (or timeout-secs 10))]
    (zero? (:exit (proc/shell {:dir dir :out :string :err :string :continue true}
                              "timeout" t "git" "ls-remote" "--heads" remote-name)))))

(defn deploy-get-default-branch [dir remote-name]
  (let [result (git-out dir "ls-remote" "--symref" remote-name "HEAD")]
    (or (when result
          (some #(second (re-matches #"ref:\s+refs/heads/(\S+)\s+HEAD" %))
                (str/split-lines result)))
        ;; Fallback: check common names
        (let [branches (->> (str/split-lines (or (git-out dir "ls-remote" "--heads" remote-name) ""))
                            (keep #(second (re-matches #".*refs/heads/(.+)" %))))]
          (or (some #{"main"} branches)
              (some #{"master"} branches)
              (some #{"develop"} branches)
              (first branches))))))

(defn deploy-show-key-instructions [key-file]
  (println)
  (println "========================================")
  (println "DEPLOY KEY NOT YET AUTHORIZED")
  (println "========================================")
  (println)
  (println "Add this public key as a deploy key on your git server:")
  (println)
  (print (slurp (str key-file ".pub")))
  (println)
  (println "========================================")
  (println)
  (println "For GitHub: Settings \u2192 Deploy keys \u2192 Add deploy key")
  (println "For GitLab: Settings \u2192 Repository \u2192 Deploy keys")
  (println "For Forgejo/Gitea: Settings \u2192 Deploy Keys \u2192 Add Deploy Key")
  (println))

;;; --- Deploy Help ---

(def deploy-help-text
  "## git deploy - Clone a repository using a deploy key

Usage: git deploy <repo-url[#branch]> [destination] [options]
       git deploy <path> [options]

Arguments:
    repo-url        Repository URL (supports #branch suffix)
    destination     Local directory (default: ~/git/vendor/{ORG}/{REPO})
    path            Path to existing git repo (converts remote to deploy key)

Options:
    --remote <name>    Remote name (default: origin)
    --branch <name>    Branch to clone (overrides #branch in URL)
    -h, --help         Show this help message

Description:
    Clones a repository using a dedicated deploy key for authentication,
    or converts an existing repository's remote to use a deploy key.

    When given a URL:
    - Creates a new clone using a deploy key for authentication

    When given a path to an existing git repository:
    - Offers to convert the existing remote to use a deploy key
    - If no remote exists, prompts for a URL
    - If already configured, tests the deploy key

    If the deploy key is already authorized:
    - Discovers the default branch automatically (if not specified)
    - Fetches and checks out the repository
    - Exits successfully (code 0)

    If the deploy key is NOT yet authorized:
    - Creates the deploy key and shows the public key
    - Prints instructions to add it to your git server
    - Exits with error code 1 (re-run after adding the key)

URL Formats:
    git@github.com:user/repo.git
    git@github.com:user/repo.git#main
    https://github.com/user/repo
    https://github.com/user/repo#develop
    ssh://git@host:port/user/repo.git

Examples:
    git deploy git@github.com:user/repo.git
    git deploy git@github.com:user/repo.git#develop
    git deploy git@github.com:user/repo.git ~/projects/myrepo
    git deploy /path/to/existing/repo
    git deploy .

Workflow:
    1. Run 'git deploy <url>' or 'git deploy <path>'
    2. If key not yet authorized, add the printed key to your git server
    3. Re-run the command - repository will be cloned/configured")

;;; --- Deploy: Parse CLI args ---

(defn deploy-parse-args [args]
  (loop [[arg & more] args
         opts {:repo-spec nil :destination nil :remote "origin" :branch-override nil}]
    (if (nil? arg)
      opts
      (case arg
        "--remote" (recur (rest more) (assoc opts :remote (first more)))
        "--branch" (recur (rest more) (assoc opts :branch-override (first more)))
        ("-h" "--help") (do (println deploy-help-text) (System/exit 0))
        (if (str/starts-with? arg "-")
          (do (error "Unknown option:" arg) (println deploy-help-text) (System/exit 1))
          (cond
            (nil? (:repo-spec opts)) (recur more (assoc opts :repo-spec arg))
            (nil? (:destination opts)) (recur more (assoc opts :destination arg))
            :else (do (error "Too many arguments")
                      (println deploy-help-text)
                      (System/exit 1))))))))

;;; --- Deploy: Clone success handler ---

(defn deploy-clone-success [dir remote branch]
  (let [branch (or branch
                   (do (stderr "## Discovering default branch...")
                       (let [b (deploy-get-default-branch dir remote)]
                         (when b (stderr (str "## Default branch: " b)))
                         b)))]
    (if (str/blank? branch)
      (do (stderr)
          (stderr "========================================")
          (stderr "## Repository is empty (no branches on remote)")
          (stderr (str "## Location: " dir))
          (stderr "========================================"))
      (do (stderr (str "## Fetching from " remote "..."))
          (git! dir "fetch" remote)
          (stderr (str "## Checking out branch '" branch "'..."))
          (git! dir "checkout" branch)
          (proc/shell {:dir dir :continue true}
                      "git" "branch" (str "--set-upstream-to=" remote "/" branch) branch)
          (stderr)
          (stderr "========================================")
          (stderr "## Repository cloned successfully!")
          (stderr (str "## Location: " dir))
          (stderr (str "## Branch: " branch))
          (stderr "========================================")))))

;;; --- Deploy: Key failure handler ---

(defn deploy-key-failure [key-file dest convert-mode?]
  (when (and key-file (fs/exists? (str key-file ".pub")))
    (deploy-show-key-instructions key-file))
  (stderr)
  (stderr (str "## Repository prepared at: " dest))
  (stderr "## After adding the deploy key, run this command again:")
  (if convert-mode?
    (stderr "##   git deploy")
    (stderr (str "##   git deploy " (str/join " " original-args))))
  (stderr)
  (System/exit 1))

;;; --- Deploy Main ---

(defn deploy-main [args]
  (check-deps "git" "ssh-keygen")
  (let [{:keys [repo-spec destination remote branch-override]} (deploy-parse-args args)]
    (when (str/blank? repo-spec)
      (println deploy-help-text)
      (System/exit 0))

    ;; Validate: must be a directory or a URL
    (let [is-dir (fs/directory? repo-spec)
          is-url (boolean (re-find #"^(git@|ssh://|https?://)" (or repo-spec "")))]
      (when (and (not is-dir) (not is-url))
        (fault (str "Invalid argument: '" repo-spec "' is not a directory or a valid URL")))

      (if is-dir
        ;; ---- Convert mode ----
        (let [target-dir (str (fs/absolutize repo-spec))]
          (when-not (git-ok? target-dir "rev-parse" "--git-dir")
            (fault (str "Directory is not a git repository: " target-dir)))
          (let [existing-url (git-out target-dir "remote" "get-url" remote)
                already-configured (and existing-url (deploy-alias-url? existing-url))
                repo-spec (cond
                            (nil? existing-url)
                            (do (println)
                                (println (str "Repository has no '" remote "' remote configured."))
                                (println)
                                (let [url (ask-input "Enter repository URL:")]
                                  (when (str/blank? url) (fault "No URL provided"))
                                  url))

                            already-configured existing-url

                            :else
                            (do (println)
                                (println (str "Found existing remote '" remote "':"))
                                (println (str "  " existing-url))
                                (println)
                                (if (ask-yes-no "Convert this remote to use a deploy key?" "y")
                                  existing-url
                                  (do (println "Aborted.") (System/exit 0)))))
                {:keys [url branch]} (deploy-parse-repo-spec repo-spec)
                branch (or branch-override branch)
                repo-port (when-not already-configured
                            (second (re-find #"^ssh://(?:[^@]+@)?[^:/]+:([0-9]+)/" url)))
                url (if already-configured url (deploy-normalize-url url))]

            (stderr)
            (stderr (str "## Repository URL: " url))
            (stderr (str "## Destination: " target-dir))
            (when branch (stderr (str "## Branch: " branch)))
            (stderr)

            (let [key-info (if already-configured
                             (let [alias (deploy-extract-alias url)]
                               (stderr (str "## Deploy key already configured: " alias))
                               {:key-file (deploy-key-file-path alias)})
                             (do (deploy-init-repo target-dir url remote)
                                 (stderr)
                                 (stderr "## Setting up deploy key...")
                                 (deploy-setup-key target-dir remote repo-port)))]
              (stderr)
              (stderr "## Testing deploy key...")
              (if (deploy-test-key target-dir remote)
                (do (stderr "## Deploy key is working!")
                    (stderr)
                    (stderr "========================================")
                    (stderr (if already-configured
                              "## Deploy key is working!"
                              "## Remote converted to deploy key successfully!"))
                    (stderr (str "## Location: " target-dir))
                    (stderr "========================================"))
                (deploy-key-failure (:key-file key-info) target-dir true)))))

        ;; ---- Clone mode ----
        (let [{:keys [url branch]} (deploy-parse-repo-spec repo-spec)
              branch (or branch-override branch)
              repo-port (second (re-find #"^ssh://(?:[^@]+@)?[^:/]+:([0-9]+)/" url))
              url (deploy-normalize-url url)
              dest (or destination (deploy-default-destination url))
              dest (if (str/starts-with? dest "/") dest
                       (str (System/getProperty "user.dir") "/" dest))]

          (stderr)
          (stderr (str "## Repository URL: " url))
          (stderr (str "## Destination: " dest))
          (when branch (stderr (str "## Branch: " branch)))
          (stderr)

          (deploy-init-repo dest url remote)
          (stderr)
          (stderr "## Setting up deploy key...")
          (let [key-info (deploy-setup-key dest remote repo-port)]
            (stderr)
            (stderr "## Testing deploy key...")
            (if (deploy-test-key dest remote)
              (do (stderr "## Deploy key is working!")
                  (deploy-clone-success dest remote branch))
              (deploy-key-failure (:key-file key-info) dest false))))))))

;;; ============================================================
;;; Deploy-Key Extension
;;; ============================================================

(defn deploy-key-list []
  (let [keys-dir (str home "/.ssh/deploy-keys")]
    (if-not (fs/directory? keys-dir)
      (println "No deploy keys found.")
      (let [key-files (->> (fs/list-dir keys-dir)
                           (map str)
                           (remove #(str/ends-with? % ".pub"))
                           (filter #(fs/regular-file? %))
                           sort)]
        (if (empty? key-files)
          (println "No deploy keys found.")
          (do (println "Deploy keys:")
              (println)
              (doseq [key-file key-files]
                (let [alias (fs/file-name key-file)
                      pub-file (str key-file ".pub")
                      config-content (when (fs/exists? ssh-config-file)
                                       (slurp ssh-config-file))
                      in-config (and config-content
                                     (some #(= (str/trim %) (str "Host " alias))
                                           (str/split-lines config-content)))
                      hostname (when in-config
                                 ;; Extract HostName from the block
                                 (let [lines (str/split-lines config-content)]
                                   (loop [[line & more] lines found false]
                                     (when line
                                       (if (re-matches #"Host .+" line)
                                         (recur more (= (str/trim line) (str "Host " alias)))
                                         (if (and found (re-find #"HostName" line))
                                           (str/trim (second (str/split (str/trim line) #"\s+" 2)))
                                           (recur more found)))))))]
                  (println (str "  " alias))
                  (when hostname (println (str "    Host: " hostname)))
                  (println (str "    Key:  " key-file))
                  (println (str "    SSH config: " (if in-config "yes" "no")))
                  (when (fs/exists? pub-file)
                    (let [result (proc/shell {:out :string :err :string :continue true}
                                            "ssh-keygen" "-lf" pub-file)]
                      (when (zero? (:exit result))
                        (let [fingerprint (second (str/split (str/trim (:out result)) #"\s+"))]
                          (when fingerprint
                            (println (str "    Fingerprint: " fingerprint)))))))
                  (println)))))))))

(defn deploy-key-show [alias]
  (when (str/blank? alias)
    (error "Missing alias argument")
    (System/exit 1))
  (let [pub-file (str home "/.ssh/deploy-keys/" alias ".pub")]
    (when-not (fs/exists? pub-file)
      (fault (str "Deploy key not found: " alias)))
    (println (str "Public key for " alias ":"))
    (println)
    (print (slurp pub-file))
    (println)))

(defn deploy-key-remove [alias]
  (when (str/blank? alias)
    (error "Missing alias argument")
    (System/exit 1))
  (let [keys-dir (str home "/.ssh/deploy-keys")
        key-file (str keys-dir "/" alias)
        pub-file (str key-file ".pub")]
    (let [found (atom false)]
      ;; Remove from SSH config
      (when (and (fs/exists? ssh-config-file)
                 (some #(= (str/trim %) (str "Host " alias))
                       (str/split-lines (slurp ssh-config-file))))
        (spit ssh-config-file (remove-host-block (slurp ssh-config-file) alias))
        (fs/set-posix-file-permissions ssh-config-file "rw-------")
        (println (str "Removed SSH config entry: " alias))
        (reset! found true))
      ;; Remove key files
      (when (fs/exists? key-file)
        (fs/delete key-file)
        (println (str "Removed private key: " key-file))
        (reset! found true))
      (when (fs/exists? pub-file)
        (fs/delete pub-file)
        (println (str "Removed public key: " pub-file))
        (reset! found true))
      (when-not @found
        (fault (str "Deploy key not found: " alias)))
      (println)
      (println (str "Deploy key '" alias "' removed successfully."))
      (println)
      (println "Note: If any repositories are using this key, you'll need to")
      (println "update their remote URLs or create a new deploy key."))))

(def deploy-key-help-text
  "## git deploy-key - Manage deploy keys

Usage: git deploy-key <command> [args]

Commands:
    list              List all deploy keys
    show <alias>      Show the public key for an alias
    remove <alias>    Remove a deploy key and its SSH config entry

Options:
    -h, --help        Show this help message

Examples:
    git deploy-key list
    git deploy-key show deploy--github.com--user-repo
    git deploy-key remove deploy--github.com--user-repo

Files:
    Keys:   ~/.ssh/deploy-keys/
    Config: ~/.ssh/config")

(defn deploy-key-main [args]
  (let [[subcommand & rest-args] args]
    (case subcommand
      ("list" "ls") (deploy-key-list)
      ("show" "cat") (deploy-key-show (first rest-args))
      ("remove" "rm" "delete") (deploy-key-remove (first rest-args))
      ("-h" "--help" "help" nil) (do (println deploy-key-help-text) (System/exit 0))
      (do (error "Unknown command:" subcommand)
          (println deploy-key-help-text)
          (System/exit 1)))))

;;; ============================================================
;;; Vendor Extension
;;; ============================================================

(def vendor-default-domain "github.com")

(defn vendor-parse-ref
  "Parse a git repository reference into {:domain :org :repo :ssh? :ssh-port}."
  [input]
  (let [input (str/replace input #"/$" "")]
    (or
     ;; https://domain/org/repo
     (when-let [[_ domain org repo] (re-matches #"https?://([^/]+)/([^/]+)/([^/]+)/?" input)]
       {:domain domain :org org :repo repo :ssh? false})

     ;; ssh://[git@]domain[:port]/org/repo
     (when-let [[_ _ domain _ port org repo]
                (re-matches #"ssh://(git@)?([^/:]+)(:([0-9]+))?/([^/]+)/(.+)" input)]
       {:domain domain :org org :repo repo :ssh? true :ssh-port port})

     ;; git@domain:org/repo
     (when-let [[_ domain org repo] (re-matches #"git@([^:]+):([^/]+)/(.+)" input)]
       {:domain domain :org org :repo repo :ssh? true})

     ;; domain/org/repo (three parts, first has dots)
     (when-let [[_ domain org repo]
                (re-matches #"([a-zA-Z0-9.-]+\.[a-zA-Z]+)/([^/]+)/([^/]+)" input)]
       {:domain domain :org org :repo repo :ssh? false})

     ;; org/repo (two parts, default domain)
     (when-let [[_ org repo] (re-matches #"([^/]+)/([^/]+)" input)]
       {:domain vendor-default-domain :org org :repo repo :ssh? false}))))

(defn vendor-normalize [{:keys [repo org] :as parsed}]
  (-> parsed
      (assoc :repo (str/replace repo #"\.git$" ""))
      (assoc :org (str/lower-case org))))

(defn vendor-build-url [{:keys [domain org repo ssh? ssh-port]}]
  (if ssh?
    (if ssh-port
      (str "ssh://git@" domain ":" ssh-port "/" org "/" repo ".git")
      (str "git@" domain ":" org "/" repo ".git"))
    (str "https://" domain "/" org "/" repo)))

(def vendor-help-text
  "## git vendor - Clone repositories to ~/git/vendor/{org}/{repo}

Usage: git vendor <repository>

Arguments:
    repository      Repository reference in any supported format

Supported Formats:
    org/repo                          Uses github.com by default
    github.com/org/repo               Domain with path
    https://github.com/org/repo       HTTPS URL
    git@github.com:org/repo.git       SSH URL
    ssh://git@host:port/org/repo      SSH URL with custom port

Options:
    -h, --help      Show this help message

Description:
    Clones a repository to ~/git/vendor/{org}/{repo}.
    The org name is lowercased for consistent directory structure.

    If the repository already exists, reports the location and exits.

Examples:
    git vendor enigmacurry/sway-home
    git vendor github.com/enigmacurry/sway-home
    git vendor https://github.com/EnigmaCurry/sway-home.git
    git vendor git@github.com:EnigmaCurry/sway-home.git
    git vendor ssh://git@github.com:22/EnigmaCurry/sway-home.git")

(defn vendor-main [args]
  (check-deps "git")
  (let [repo-ref (loop [[arg & more] args ref nil]
                   (if (nil? arg)
                     ref
                     (case arg
                       ("-h" "--help") (do (println vendor-help-text) (System/exit 0))
                       (if (str/starts-with? arg "-")
                         (do (error "Unknown option:" arg)
                             (println vendor-help-text) (System/exit 1))
                         (if (nil? ref)
                           (recur more arg)
                           (do (error "Too many arguments")
                               (println vendor-help-text) (System/exit 1)))))))]
    (when (str/blank? repo-ref)
      (println vendor-help-text)
      (System/exit 0))
    (let [parsed (vendor-parse-ref repo-ref)]
      (when-not parsed
        (error "Invalid repository format:" repo-ref)
        (println)
        (println "Supported formats:")
        (println "  org/repo")
        (println "  github.com/org/repo")
        (println "  https://github.com/org/repo")
        (println "  git@github.com:org/repo.git")
        (println "  ssh://git@host:port/org/repo")
        (System/exit 1))
      (let [{:keys [org repo] :as parsed} (vendor-normalize parsed)
            clone-url (vendor-build-url parsed)
            vendor-dir (str home "/git/vendor")
            target-dir (str vendor-dir "/" org "/" repo)]
        (if (fs/directory? target-dir)
          (do (println (str "Repository already exists: " target-dir))
              (System/exit 0))
          (do (fs/create-dirs (str vendor-dir "/" org))
              (println (str "Cloning " clone-url))
              (println (str "     to " target-dir))
              (println)
              (if (zero? (:exit (proc/shell {:continue true} "git" "clone" clone-url target-dir)))
                (do (println)
                    (println (str "Repository cloned: " target-dir)))
                (fault "Clone failed"))))))))

;;; ============================================================
;;; Remote-Proto Extension
;;; ============================================================

(defn remote-proto-parse-url
  "Parse a git remote URL into {:host :org :repo :port}."
  [url]
  (let [url (str/replace url #"\.git$" "")]
    (or (when-let [[_ host org repo] (re-matches #"https?://([^/]+)/([^/]+)/([^/]+)/?" url)]
          {:host host :org org :repo repo})
        (when-let [[_ _ host _ port org repo]
                   (re-matches #"ssh://(git@)?([^/:]+)(:([0-9]+))?/([^/]+)/([^/]+)/?" url)]
          {:host host :org org :repo repo :port port})
        (when-let [[_ host org repo] (re-matches #"git@([^:]+):([^/]+)/([^/]+)" url)]
          {:host host :org org :repo repo}))))

(defn remote-proto-build-url [{:keys [host org repo port]} protocol]
  (case protocol
    ("http" "https") (str "https://" host "/" org "/" repo ".git")
    "git"            (str "git@" host ":" org "/" repo ".git")
    "ssh"            (if port
                       (str "ssh://git@" host ":" port "/" org "/" repo ".git")
                       (str "ssh://git@" host "/" org "/" repo ".git"))))

(def remote-proto-help-text
  "## git remote-proto - Convert remote URL protocol

Usage: git remote-proto <protocol> [options]

Arguments:
    protocol        Target protocol: http, https, git, or ssh

Protocols:
    http, https     https://{host}/{org}/{repo}.git
    git             git@{host}:{org}/{repo}.git
    ssh             ssh://git@{host}[:port]/{org}/{repo}.git

Options:
    --remote <name>    Remote name (default: origin)
    --port <port>      SSH port (only used with ssh protocol)
    -h, --help         Show this help message

Description:
    Converts the remote URL to use a different protocol while
    preserving the host, organization, and repository.

Examples:
    git remote-proto git
    git remote-proto https
    git remote-proto ssh --port 2222
    git remote-proto ssh --remote upstream")

(defn remote-proto-main [args]
  (check-deps "git")
  (let [parsed (loop [[arg & more] args
                      opts {:protocol nil :remote "origin" :port nil}]
                 (if (nil? arg)
                   opts
                   (case arg
                     "--remote" (recur (rest more) (assoc opts :remote (first more)))
                     "--port" (recur (rest more) (assoc opts :port (first more)))
                     ("-h" "--help") (do (println remote-proto-help-text) (System/exit 0))
                     (if (str/starts-with? arg "-")
                       (do (error "Unknown option:" arg)
                           (println remote-proto-help-text) (System/exit 1))
                       (if (nil? (:protocol opts))
                         (recur more (assoc opts :protocol arg))
                         (do (error "Too many arguments")
                             (println remote-proto-help-text) (System/exit 1)))))))
        {:keys [protocol remote port]} parsed]

    (when (str/blank? protocol)
      (println remote-proto-help-text)
      (System/exit 0))

    (when-not (#{"http" "https" "git" "ssh"} protocol)
      (fault (str "Invalid protocol: " protocol " (must be http, https, git, or ssh)")))

    (when (and port (not= protocol "ssh"))
      (stderr "Warning: --port is only used with ssh protocol, ignoring"))

    (let [cwd (System/getProperty "user.dir")]
      (when-not (git-ok? cwd "rev-parse" "--git-dir")
        (fault "Not a git repository"))

      (let [current-url (or (git-out cwd "remote" "get-url" remote)
                            (fault (str "Remote '" remote "' not found")))]
        (println (str "Current: " current-url))

        (let [parsed (or (remote-proto-parse-url current-url)
                         (fault (str "Cannot parse remote URL: " current-url)))
              parsed (if (and (= protocol "ssh") port)
                       (assoc parsed :port port)
                       parsed)
              new-url (remote-proto-build-url parsed protocol)]

          (if (= current-url new-url)
            (println (str "Already using " protocol " protocol"))
            (do (git! cwd "remote" "set-url" remote new-url)
                (println (str "Updated: " new-url)))))))))

;;; ============================================================
;;; Main Dispatcher
;;; ============================================================

(def main-help-text
  "## Git Extensions Framework

Usage: git <extension> [args...]
   or: git-<extension> [args...]

Available extensions:
    vendor        Clone repositories to ~/git/vendor/{org}/{repo}
    deploy        Clone repositories using deploy key authentication
    deploy-key    Manage deploy keys (list, show, remove)
    remote-proto  Convert remote URL protocol (https, git, ssh)

Run 'git <extension> --help' for extension-specific help.

Setup:
    Create symlinks in your PATH:
        ln -s /path/to/git_extensions.bb ~/.local/bin/git-vendor
        ln -s /path/to/git_extensions.bb ~/.local/bin/git-deploy
        ln -s /path/to/git_extensions.bb ~/.local/bin/git-deploy-key
        ln -s /path/to/git_extensions.bb ~/.local/bin/git-remote-proto

    Then use as:
        git vendor org/repo
        git deploy <repo-url>
        git deploy-key list
        git remote-proto ssh")

(defn- find-git-cmd
  "Scan a sequence of argv strings for one starting with 'git-'.
   Returns the extension name (e.g. 'deploy') or nil."
  [parts]
  (some (fn [part]
          (let [base (str (fs/file-name part))]
            (when (str/starts-with? base "git-")
              (subs base 4))))
        parts))

(defn- detect-from-procfs
  "Linux: read /proc/self/cmdline (null-separated argv)."
  []
  (let [bytes (java.nio.file.Files/readAllBytes
               (java.nio.file.Paths/get "/proc/self/cmdline" (into-array String [])))
        parts (loop [i 0 start 0 result []]
                (if (>= i (alength bytes))
                  (if (> i start)
                    (conj result (String. bytes (int start) (int (- i start))))
                    result)
                  (if (zero? (aget bytes i))
                    (recur (inc i) (inc i)
                           (if (> i start)
                             (conj result (String. bytes (int start) (int (- i start))))
                             result))
                    (recur (inc i) start result))))]
    (find-git-cmd parts)))

(defn- detect-from-ps
  "macOS/BSD: use ps to read the command line for the current process."
  []
  (let [pid (.pid (java.lang.ProcessHandle/current))
        result (proc/shell {:out :string :err :string :continue true}
                           "ps" "-p" (str pid) "-o" "args=")
        parts (when (zero? (:exit result))
                (str/split (str/trim (:out result)) #"\s+"))]
    (find-git-cmd parts)))

(defn detect-extension-cmd
  "Detect the extension command from the invoked symlink name.
   Tries /proc/self/cmdline (Linux), then ps (macOS/BSD)."
  []
  (or (try (detect-from-procfs) (catch Exception _ nil))
      (try (detect-from-ps) (catch Exception _ nil))))

(let [symlink-cmd (detect-extension-cmd)
      ;; If invoked via symlink (git-deploy), use that command and all CLI args
      ;; If invoked directly (bb git_extensions.bb deploy ...), first arg is the command
      extension-cmd (or symlink-cmd (first *command-line-args*))
      args (if symlink-cmd
             (vec *command-line-args*)
             (vec (rest *command-line-args*)))]
  (case extension-cmd
    "vendor"       (vendor-main args)
    "deploy"       (deploy-main args)
    "deploy-key"   (deploy-key-main args)
    "remote-proto" (remote-proto-main args)
    ("-h" "--help" "help" nil) (do (println main-help-text) (System/exit 0))
    (do (error "Unknown extension:" extension-cmd)
        (println main-help-text)
        (System/exit 1))))
