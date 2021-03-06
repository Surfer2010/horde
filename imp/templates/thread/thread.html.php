<h1 class="header variableLengthHeader">
 <?php echo ($this->thread ? _("Thread Display") : _("Multiple Message View")) ?>:
 <?php echo $this->subject ?>
<?php if ($this->delete): ?>
 <?php echo $this->delete ?><span class="iconImg deleteImg"></span></a>
<?php endif; ?>
</h1>

<a id="display"></a>
<div class="solidbox striped threadSummary">
<?php foreach ($this->tree as $v): ?>
 <div><?php echo $v['subject'] ?></div>
<?php endforeach; ?>
</div>

<?php foreach ($this->messages as $v): ?>
<a id="i<?php echo $v['idx'] ?>"></a>
<div class="solidbox threadBox">
 <div class="control">
  <span class="threadlink"><?php echo $v['link'] ?></span>
  <strong><?php echo ($v['addr_to'] ? _("To") : _("From")) ?>:</strong>
  <?php echo $v['addr'] ?>
  (<small><?php echo $v['date'] ?></small>)
 </div>

 <div class="messageBody">
  <?php echo $v['body'] ?>
 </div>
</div>
<?php endforeach; ?>
