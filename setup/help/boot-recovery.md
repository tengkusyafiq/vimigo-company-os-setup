# If your computer won't start after the Cowork fix

Nothing is lost. Your files are safe. This puts Windows back the way it was
before the change.

## The clicking way (try this first)

1. Turn the computer on. If Windows fails to start twice, it opens a blue
   screen by itself. (Or hold **Shift** while clicking **Restart**.)
2. Click **Troubleshoot**.
3. Click **Advanced options**.
4. Click **System Restore**.
5. If it asks for a **BitLocker recovery key**, it is in your Microsoft account —
   on your phone, open **aka.ms/myrecoverykey** and sign in.
6. Pick the restore point called **Before Cowork fix**, then **Next**, then **Finish**.
7. Wait. The computer restarts on its own, back to normal.

## If System Restore fails

From the same blue screen: **Troubleshoot → Advanced options → Command Prompt**
(needs the BitLocker key if the drive is encrypted), then:

    bcdedit /set {default} hypervisorlaunchtype off

Close the window, choose **Continue**. Windows starts without the virtualization
layer that failed. Cowork will not work on this laptop; Claude Code will.
