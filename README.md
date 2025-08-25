[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/schichtel)](https://artifacthub.io/packages/search?repo=schichtel)

Helm Charts
===========

This is a collection of Helm Charts that I have built from scratch or forked from other repositories.

The primary focus of all of these charts is cover my personal use-cases, however anyone is free to use them. **Pull requests, issues and discussions** are always welcome!

**All charts that exist on the `master` branch should work and can be considered maintained, even if they have not seen any changes recently.**
If a chart has unreleased modifications that you want, please just ask for a release or open a PR to bump the version.

**Pull requests, issues and discussions are welcome!**

Find the project at https://github.com/pschichtel/helm-charts.

Documentation
-------------

You might have noticed the lack of documentation. This is not accident or pure lazyness.

Most charts I use on a daily basis, personally or professionally, have misleading or wrong documentation, which has cost me a lot time over the years. I usually go straight to the templates, skipping any documentation that might exist, if anything doesn't behave as expected. I'd encourage anyone to do the same.

I generally aim to create narrow-focused charts that are aligned with typical conventions where it makes sense. I don't expect documentation to add significant value here.

Some charts will however have inline docuentation in templates or their `values.yaml`, primarily to document unique things done by the chart that might not be clear from the context.

Versioning
----------

I intent to follow [semver](https://semver.org/), however individual charts might use different version schemes.

Most charts here are still `0.*.*` (unstable), not because I intent to do breaking changes, but because I haven't had a good reason yet to declare it stable. If you want some form of stability promise, please raise your voice.

Quality of Charts
-----------------

The charts are of various quality. I generally try to:

* stick closely to `helm create`'s structure
* align with common patterns seen throughout the eco system
* support multiple installations in a single namespace

Not all of the charts will check all those boxes. Some are old enough, that `helm create`'s output was different. Some started out as a fork, which itself didn't adhere to these rules. What ever the reaons might be, don't expect perfect consistency. I intentionally don't use a complex template library similar to what e.g. bitnami does, to keep things simpler and to be able to more easily adjust to the specific use-case.

I generally apply the boy scout rule (leave the site cleaner than you found it) and I would prefer PR authors to do the same.

Requests for new Charts
-----------------------

I won't accept requests for new charts, unless *I* have a use for them or the request is accompanied with some form of sponsoring.

Also no additional users will receive commit access to this repository, please fork and create PRs.
