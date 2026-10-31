# Git 命令速查手册

> 按"使用场景"编排，不是按字母表。想做什么，就找对应的那一段。
> 最后更新：2026-10-31

---

## 0. 先记住这张图

**工作区 →（add）→ 暂存区 →（commit）→ 本地仓库 →（push）→ 远程仓库**

反过来就是退：`restore` 退一步、`reset` 退一步、`pull` 从云端取回。

| 阶段 | 它是什么 | 往前走（→） | 往后退（←） |
|---|---|---|---|
| ① 工作区 | 你正在改的文件 | `git add` 装箱 | `git restore` 还原 |
| ② 暂存区 | 已装箱待发的清单 | `git commit` 封箱 | `git reset` 拆箱 |
| ③ 本地仓库 | 本机档案室，存全部历史 | `git push` 发货上云 | `git pull` 从云端取回 |
| ④ 远程仓库 | GitHub，换电脑也在 | —— | —— |

三个核心认知：

1. **提交是快照，不是差异** —— 每次提交都存下当时整个项目的完整样子
2. **分支只是一个指针** —— 创建分支不复制任何文件，所以快到没感觉
3. **几乎不会真的丢东西** —— 只要提交过，`git reflog` 都能捞回来

---

## 1. 开局：从零到有仓库

| 命令 | 场景 |
|---|---|
| `git init` | 把一个普通文件夹变成 Git 仓库（只做一次） |
| `git init -b main` | 同上，但初始分支直接命名为 main（避免默认 master） |
| `git clone <地址>` | 把已有仓库（自己的或别人的）完整复制到本地 |
| `git config --global user.name "名字"` | 首次使用，告诉 Git 你是谁 |
| `git config --global user.email "邮箱"` | 同上（邮箱最好与 GitHub 一致） |
| `git config --list` | 查看当前所有配置 |

---

## 2. 日常三连：看、装、封

| 命令 | 场景 |
|---|---|
| `git status` | **最高频**。随时看：改了哪些、哪些没提交 |
| `git status -sb` | 精简版，一行一个文件，适合经常敲 |
| `git add 文件名` | 把某个文件装进暂存区（准备提交） |
| `git add .` | 把所有改动装进去（最常用） |
| `git add -A` | 同上，但连删除操作也一并记录（更彻底） |
| `git commit -m "说明"` | 封存一版，生成档案编号 |
| `git commit -am "说明"` | 跳过 add，直接提交"已跟踪文件"的改动（新文件不生效） |
| `git diff` | 看具体改了哪几行（还没 add 的改动） |
| `git diff --staged` | 看已 add、即将提交的内容 |

### 提交说明怎么写

好习惯：`类型: 做了什么`

```
feat: 添加登录页面
fix: 修复首页按钮错位
docs: 补充使用说明
refactor: 拆分工具函数
style: 统一缩进
chore: 升级依赖
```

一句话原则：**看这条说明，能知道这次改了什么，而不用点进去看代码。**

---

## 3. 撤销与后悔（最重要的一节）

先把 `HEAD~1` 记住：`HEAD` 是"现在"，`~1` 是往回一格，`~3` 是往回三格。

| 命令 | 场景 | 危险度 |
|---|---|---|
| `git restore 文件` | 改了但没提交，想扔掉这个文件的所有改动 | ⚠️ 改动消失 |
| `git restore .` | 扔掉全部未提交改动 | ⚠️ 改动消失 |
| `git restore --staged 文件` | 已 add，但想从暂存区拿出来（改动保留） | ✅ 安全 |
| `git reset --soft HEAD~1` | 撤销最近一次提交，改动回到暂存区 | ✅ 最安全 |
| `git reset --mixed HEAD~1` | 撤销提交，改动回到工作区（默认行为） | ✅ 安全 |
| `git reset --hard HEAD~1` | 撤销提交 + 连改动一起抹掉 | 🔴 高危 |
| `git revert <提交号>` | 撤销一次已推送的提交（生成反向新提交） | ✅ 安全 |
| `git reflog` | 查看 HEAD 走过的每一步，找回"丢失"的提交 | ✅ 救命 |
| `git branch 救援 HEAD@{2}` | 给某个历史状态建分支（比硬 reset 稳妥） | ✅ 安全 |
| `git rm --cached 文件` | 让文件脱离版本管理，但保留硬盘上的文件 | ✅ 安全 |

### 选择逻辑

- 没提交 → `restore`
- 提交了没推送 → `reset --soft`
- 推送了 → `revert`（**不要** reset + 强推）
- 全乱了 → `reflog` 找回来

### reset 三个参数的区别

撤销提交后，改动去哪了？

- `--soft`：回到暂存区（还准备提交的状态）
- `--mixed`：回到工作区（需要重新 add）
- `--hard`：直接蒸发

---

## 4. 远程：和 GitHub 打交道

| 命令 | 场景 |
|---|---|
| `git remote -v` | 查看当前绑定的是哪个远程仓库 |
| `git remote add origin <地址>` | 首次绑定远程仓库 |
| `git remote set-url origin <新地址>` | 换远程地址 |
| `git push -u origin main` | 首次推送，并建立追踪关系（之后只需 git push） |
| `git push` | 日常推送 |
| `git pull` | 拉取云端更新并合并（= fetch + merge） |
| `git fetch` | 只把云端更新取下来，**不动你的文件**（更安全） |
| `git fetch` 后 `git log origin/main --oneline` | 先看清云端改了什么，再决定是否合并 |

### fetch 和 pull 的区别

- `fetch`：把云端的消息取回来放在"信箱"，你的文件不动。**安全的看新闻**
- `pull`：取回来并直接合并进你的文件。**可能触发冲突**

保守习惯：先 `fetch` 看看，再 `pull`。

### origin/main 是什么

不是"实时云端状态"，而是**上次同步时云端的样子**，存在你本地的快照。

---

## 5. 分支：Git 的灵魂

| 命令 | 场景 |
|---|---|
| `git branch` | 列出本地分支（带 * 的是当前所在） |
| `git branch -a` | 连远程分支一起列出 |
| `git switch 分支名` | 切换到某个分支 |
| `git switch -c 新分支` | 创建并立刻切过去（最常用） |
| `git branch -d 分支名` | 删除已合并的分支 |
| `git branch -D 分支名` | 强制删除（未合并也删） |
| `git merge 分支名` | 把某分支合并进当前分支 |
| `git log --oneline --graph --all` | 用图形看分支时间线（非常直观） |

> 旧写法 `git checkout` 管所有事，新版拆成了 `switch`（切分支）和 `restore`（还原文件）。用新命令更不容易误操作。

### 冲突是怎么处理的

合并时若两人改了同一行，Git 会在文件里插入标记：

```
<<<<<<< HEAD
你这一版的内容
=======
对方那一版的内容
>>>>>>> 分支名
```

处理步骤：
1. 打开文件，手动改成最终想要的样子
2. **把 `<<<<<<<`、`=======`、`>>>>>>>` 三行标记全部删掉**
3. `git add 文件`
4. `git commit`（Git 通常已备好合并提交说明）

---

## 6. 临时存放：stash

| 命令 | 场景 |
|---|---|
| `git stash` | 当前改动还不适合提交，但急着切分支，先塞进抽屉 |
| `git stash list` | 看抽屉里存了几份 |
| `git stash pop` | 取出最近一份，并从抽屉里删掉 |
| `git stash apply` | 取出但保留在抽屉里 |
| `git stash drop` | 扔掉最近一份 |

典型场景：改到一半，突然要紧急修个 bug 切去别的分支。

---

## 7. 查看与排查

| 命令 | 场景 |
|---|---|
| `git log --oneline` | 一行一条的简历史（最常用） |
| `git log --oneline -10` | 只看最近 10 条 |
| `git log -p 文件` | 看某个文件的完整改动历史 |
| `git show <提交号>` | 看某次提交具体改了什么 |
| `git blame 文件` | 每一行是谁、哪次提交改的（查"这行代码谁写的"） |
| `git ls-files` | 列出所有被 Git 管理的文件 |
| `git shortlog -sn` | 按人统计提交数 |

---

## 8. 标签：给重要版本命名

| 命令 | 场景 |
|---|---|
| `git tag v1.0.0` | 给当前提交打个标签（发版用） |
| `git tag -a v1.0.0 -m "说明"` | 带说明的标签 |
| `git tag` | 列出所有标签 |
| `git push --tags` | 把标签推到远程 |

---

## 9. 忽略文件：.gitignore

```
node_modules/      忽略整个文件夹
*.log              忽略所有 .log 文件
.env               忽略特定文件
!important.log     感叹号表示"排除例外"
```

**关键陷阱**：`.gitignore` 只对**还没被跟踪**的文件生效。
已经提交过的文件，加进忽略名单也不会自动失效，必须：

```bash
git rm --cached 文件名
git commit -m "chore: 移出版本管理"
```

---

## 10. 🔴 危险区（新手先别碰）

| 命令 | 危险在哪 |
|---|---|
| `git reset --hard` | 未提交的改动瞬间蒸发，无提示无回收站 |
| `git clean -fd` | 删除所有未跟踪的文件和文件夹，一去不返 |
| `git push --force` | 覆盖云端历史，可能毁掉别人的工作 |
| 手动删除 `.git` 文件夹 | 整个仓库身份与全部历史当场消失 |

> 记住：**改坏了文件不要紧，`.git` 才要紧。** 只要 `.git` 在，一切都还有救。

---

## 11. 二十秒上手清单

```bash
# 第一次
git init -b main
git add .
git commit -m "chore: 初始化"
git remote add origin <地址>
git push -u origin main

# 以后每次
git status
git add .
git commit -m "feat: 做了什么"
git push
```
