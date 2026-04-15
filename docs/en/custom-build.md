# Custom Build Guide

[Back to README](./README.md) | [中文](../zh/custom-build.md) | English

If your goal is to **quickly create your own image**, the easiest and most recommended option is **Custom Build** in GitHub Actions.

You can think of it like this:

> No local build environment needed. Just fill in a few options in the GitHub web UI and let GitHub build the image for you.

In most cases:

- A build-only run usually takes about **5 minutes**
- A build that also includes tests usually takes about **10 minutes**

If you just want to **try Landscape as quickly as possible** and do not need to change any settings yet, it is usually faster to download one of the prebuilt images from the repository’s **Releases** page.

---

## Quick start in 3 minutes

If this is your first time using it, just follow the steps below.

### Step 1: Open Actions

In your own fork of the repository:

- Click **Actions** in the top navigation bar
- Find **Custom Build** in the left sidebar
- Click **Run workflow**

---

### Step 2: Choose a variant

If you are not sure which one to pick, start with:

- `default`

Here is a simple way to think about the common options:

- `default`: the most general-purpose option, recommended for first-time users
- `docker`: includes Docker in the image
- `alpine`: a lighter image
- `alpine-docker`: lighter image with Docker included

If you just want to get your first successful build, **choose `default`**.

---

### Step 3: Fill in parameters as needed

Most users fall into one of these two scenarios.

#### Scenario A: You only want to change network settings

If you only want to customize LAN / DHCP settings, you can enter:

- `lan_server_ip=192.168.50.1`
- `lan_range_start=192.168.50.100`
- `lan_range_end=192.168.50.200`
- `lan_netmask=24`

What these parameters mean:

- `lan_server_ip`
  - The router’s IP address on the LAN
  - This is usually also used as the gateway and DHCP server address
  - A common value is `192.168.50.1`

- `lan_range_start`
  - The first IP address that DHCP can assign automatically
  - A common value is `192.168.50.100`

- `lan_range_end`
  - The last IP address that DHCP can assign automatically
  - A common value is `192.168.50.200`

- `lan_netmask`
  - The subnet prefix length
  - In most cases, `24` is the right choice

A few things to keep in mind:

- `lan_server_ip` should not overlap with the DHCP address pool
- `lan_range_start` and `lan_range_end` should be in the same subnet
- If you are not familiar with subnetting, using `24` is usually enough

You can leave the other fields blank or keep their default values.

#### Scenario B: You also want to change passwords

If you also want to change the login password and Web admin credentials, you can additionally enter:

- `root_password=Passw0rd!234`
- `api_username=admin`
- `api_password=Adm1n!234`

These parameters are:

- `root_password`
  - The Linux system login password
  - This affects:
    - `root`
    - `ld`

- `api_username`
  - The username for the Web admin interface

- `api_password`
  - The password for the Web admin interface

If this is just for personal use or temporary testing, entering these values directly is fine.

If you care more about security, it is better to store them in **GitHub Secrets** instead of typing them directly into the workflow form.

#### Other common input

- `landscape_version`
  - The Landscape version to build
  - If left blank, the repository default is used
  - If you are not sure, leaving it blank is usually the best choice

The current priority order is:

**direct inputs > secrets > defaults**

That means:

- If you enter a value manually in the workflow form, that value is used first
- If you leave it blank, the workflow will try to read from GitHub Secrets
- If no secret is set either, it falls back to the default value

---

### Step 4: Run the workflow

After filling in the options, click:

- **Run workflow**

Then wait for GitHub Actions to start the job.

---

### Step 5: Download the build output

After the workflow finishes:

- Open that workflow run
- Scroll down to **Artifacts**
- Download the artifact you need

The build output usually includes:

- The image file `.img`
- Build metadata `build-metadata.txt`
- The resolved configuration `effective-landscape_init.toml`

If you only want the image itself, the `.img` file is the main thing to look for.

---

## Tips

- If you only want to confirm that the image builds successfully, you do not always need to wait for every test to finish.
- As soon as the image artifact has been uploaded for that run, you can download it and try it.
- If you just want a quick first experience and do not need to change settings, downloading a prebuilt image from the **Releases** page is usually the easiest option.
- For first-time use, the safest choice is still `variant=default`, and only change the parameters you actually care about.
- If you plan to use the image long term, or you care about security, store passwords in GitHub Secrets.

---

## When to use Custom Build, and when not to

### Custom Build is recommended when

Custom Build is the better choice if:

- You forked this repository and want to generate your own image
- You do not want to set up a local Linux build environment
- You want to complete the build entirely from the GitHub web interface
- You only need to change common settings, not modify code

### Local builds are better when

A local build is a better fit if:

- You are modifying `build.sh`, files under `lib/`, files under `rootfs/`, or test scripts
- You are developing the workflow itself
- You need to debug frequently
- You need to validate local code that has not been pushed to GitHub yet

In short:

- **Want to generate an image?** Use Custom Build first.
- **Want to develop the build system itself?** Build locally.

---

## What is the best way to handle passwords?

Here is the simplest rule of thumb.

### If this is only for temporary personal use
You can enter them directly in the workflow form.

### If you plan to use it long term, or you care more about security
Use GitHub Secrets instead.

---

## What can you do after the build finishes?

After you have successfully run Custom Build once, you can also use:

- **Test Image**

This is useful for tasks like:

- Re-running validation on an existing artifact
- Running readiness or dataplane checks afterward
- Testing again with different SSH or API credentials

A simple way to think about it is:

> Custom Build creates the image. Test Image checks the image again.

---

## FAQ

### Which variant should I choose for my first run?

Choose:

- `default`

### I do not understand `landscape_version`. Do I need to set it?

Usually not. Leaving it blank is fine.

### I only want to change the LAN subnet. Can I leave everything else alone?

Yes. Just fill in the network-related parameters and leave the rest unchanged.

### Do I have to use GitHub Secrets?

Not necessarily.

If this is your personal fork, a temporary test, or convenience matters more, entering values directly in the workflow form is acceptable.

If security matters more to you, use Secrets instead.

### Where do I download the image after the workflow finishes?

Open that workflow run and download it from **Artifacts**.

---

## One-line recommendation

If your goal is:

> **“I want to create my own image as quickly as possible.”**

Start with **Custom Build**, not a local build.

Get your first image working first, then decide whether you want more advanced customization later.
