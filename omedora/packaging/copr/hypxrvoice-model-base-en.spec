# The recommended Whisper base.en ASR model, separated from the rolling daemon
# so daily source snapshots do not repeatedly rebuild a 142 MB data payload.

Name:           hypxrvoice-model-base-en
Version:        1.0.0
Release:        1%{?dist}
Summary:        Whisper base.en speech model for HypXRVoice

License:        MIT
URL:            https://github.com/openai/whisper
Source0:        https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.en.bin

BuildArch:      noarch

%description
The recommended English Whisper base model converted to the ggml format used
by HypXRVoice. It is installed separately from the rolling daemon package so
the large, stable model is downloaded only when its own package changes.

%prep
# Binary model payload; no source archive to unpack.

%build
# Data-only package.

%install
install -Dpm0644 %{SOURCE0} \
  %{buildroot}%{_datadir}/hypxrvoice/models/ggml-base.en.bin

%check
echo 'a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002  %{SOURCE0}' | \
  sha256sum -c -

%files
%dir %{_datadir}/hypxrvoice
%dir %{_datadir}/hypxrvoice/models
%{_datadir}/hypxrvoice/models/ggml-base.en.bin

%changelog
* Tue Aug 11 2026 omedora <noreply@omedora> - 1.0.0-1
- Package the pinned Whisper base.en model used by the default XR voice setup.
